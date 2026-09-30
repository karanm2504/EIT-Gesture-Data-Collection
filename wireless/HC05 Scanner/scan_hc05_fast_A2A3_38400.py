import serial
import serial.tools.list_ports
import time
import os
import multiprocessing as mp

# Must match Arduino BT_BAUD / MATLAB baudRate
BAUD_RATE = 38400

EXPECTED_REPLY = "HC05_GESTURE_DEVICE"

# MATLAB reads this file after Scan HC-05
OUTPUT_FILE = r"D:\data\HC05Scanner\last_hc05_port.txt"

PORT_TIMEOUT_SECONDS = 3


def port_number(port_name):
    digits = "".join(ch for ch in port_name if ch.isdigit())
    return int(digits) if digits else 0


def is_bluetooth_port(port_info):
    """
    With Arduino pins 0/1, Arduino USB and HC-05 share hardware Serial.
    So Arduino cannot reliably say USB_PORT_IGNORE anymore.
    Therefore the scanner should test only Windows Bluetooth COM ports.
    """
    text = " ".join([
        str(getattr(port_info, "device", "")),
        str(getattr(port_info, "name", "")),
        str(getattr(port_info, "description", "")),
        str(getattr(port_info, "hwid", "")),
        str(getattr(port_info, "manufacturer", "")),
    ]).lower()

    bluetooth_words = [
        "bluetooth",
        "bth",
        "standard serial over bluetooth",
        "rfcomm",
    ]

    usb_words = [
        "arduino",
        "ch340",
        "ch341",
        "usb-serial",
        "usb serial",
        "usb",
        "wch",
        "silicon labs",
        "cp210",
        "ftdi",
    ]

    if any(w in text for w in usb_words):
        return False

    return any(w in text for w in bluetooth_words)


def check_one_port(port_name, queue):
    ser = None

    try:
        ser = serial.Serial(
            port=port_name,
            baudrate=BAUD_RATE,
            timeout=0.6,
            write_timeout=0.6
        )

        time.sleep(0.5)
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        # Send HELLO multiple times because HC-05 can miss the first message
        for _ in range(3):
            ser.write(b"HELLO\n")
            time.sleep(0.25)

            while ser.in_waiting:
                reply = ser.readline().decode(errors="ignore").strip()

                if reply:
                    queue.put(("reply", port_name, reply))

                if EXPECTED_REPLY in reply:
                    queue.put(("found", port_name, reply))
                    return

        queue.put(("notfound", port_name, "No valid HC-05 reply"))

    except Exception as e:
        queue.put(("error", port_name, str(e)))

    finally:
        try:
            if ser is not None and ser.is_open:
                ser.close()
        except Exception:
            pass


def scan_hc05():
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)

    # Clear old result first, so MATLAB does not read stale COM port
    try:
        if os.path.isfile(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
    except Exception:
        pass

    ports = list(serial.tools.list_ports.comports())

    if not ports:
        print("No COM ports found.")
        return None

    print("Available COM ports:")
    for p in ports:
        print(f"  {p.device} - {p.description}")

    # Only scan Bluetooth COM ports.
    # This avoids accidentally selecting Arduino USB when HC-05 uses pins 0/1.
    bluetooth_ports = [p for p in ports if is_bluetooth_port(p)]

    if not bluetooth_ports:
        print("No Bluetooth COM ports found.")
        print("Pair HC-05 in Windows Bluetooth settings first.")
        print("If HC-05 is paired but not listed, remove and pair it again.")
        return None

    # Higher COM ports are often the outgoing HC-05 port, so try them first
    port_names = sorted([p.device for p in bluetooth_ports], key=port_number, reverse=True)

    print("Bluetooth scan order:")
    for p in port_names:
        print(f"  {p}")

    for port_name in port_names:
        print(f"Checking {port_name}...")

        queue = mp.Queue()
        process = mp.Process(target=check_one_port, args=(port_name, queue))
        process.start()
        process.join(PORT_TIMEOUT_SECONDS)

        if process.is_alive():
            process.terminate()
            process.join()
            print(f"Skipped {port_name}: timeout")
            continue

        while not queue.empty():
            status, p, message = queue.get()

            if status == "reply":
                print(f"Response from {p}: {message}")

            elif status == "found":
                print(f"HC-05 found on {p}")

                with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
                    f.write(p)

                print(f"Saved port to {OUTPUT_FILE}")
                return p

            elif status == "error":
                print(f"Skipped {p}: {message}")

            elif status == "notfound":
                print(f"Skipped {p}: no HC-05 reply")

    print("HC-05 not found.")
    return None


if __name__ == "__main__":
    found = scan_hc05()

    if found:
        print(f"Done: {found}")
        raise SystemExit(0)

    raise SystemExit(1)
