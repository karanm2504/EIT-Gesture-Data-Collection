# EIT Gesture Data Collection

This repository contains the software developed for an Electrical Impedance Tomography (EIT) gesture data collection system using MATLAB, Arduino, USB serial communication, and HC-05 Bluetooth communication.

The project was developed as part of the **Project Lab Embedded Systems** at the **Chair of Measurement and Sensor Technology, Technische Universität Chemnitz**.

The main objective of the project is to support gesture-based EIT data acquisition using both wired USB communication and wireless HC-05 communication.

---

## Project Overview

Electrical Impedance Tomography (EIT) is a measurement technique in which electrical currents are injected through electrodes and the resulting voltage values are measured.

In this project, the measured voltage pattern changes depending on the position of the hand and fingers. These measurements are collected and labelled using a MATLAB graphical user interface.

The system includes:

- MATLAB GUI
- Arduino Uno
- HC-05 Bluetooth module
- USB serial communication
- EIT measurement hardware
- Gesture image dataset
- Python COM-port scanner
- CSV data storage

The Arduino performs the selected EIT scan and transmits the measured voltage frames to MATLAB.

MATLAB is responsible for:

- displaying the gesture to be performed
- selecting the EIT scan type
- controlling the recording process
- receiving voltage frames
- displaying live measurement plots
- assigning gesture labels
- saving measurements into CSV files

---

## Repository Structure

```text
EIT-Gesture-Data-Collection/
│
├── docs/
│   ├── EIT_Wireless_Gesture_Data_Acquisition_Project_Report.pdf
│   └── Gesture_Data_Collection_Workflow.docx
│
├── gestures/
│   ├── A_sign.png
│   ├── B_sign.png
│   └── ...
│
├── sample-data/
│   └── example_gesture_dataset.csv
│
├── usb/
│   ├── matlab/
│   └── arduino/
│
├── wireless/
│   ├── matlab/
│   ├── arduino/
│   └── HC05Scanner/
│
├── README.md
└── .gitignore
```

---

## System Architecture

The project supports two communication methods:

1. USB serial communication
2. Wireless HC-05 Bluetooth serial communication

---

## USB Communication Workflow

```text
MATLAB GUI
    ↓
USB Serial
    ↓
Arduino Uno
    ↓
EIT Measurement Hardware
    ↓
Voltage Frames
    ↓
MATLAB
    ↓
CSV Dataset
```

The USB version provides direct serial communication between MATLAB and Arduino.

The Arduino performs the selected EIT scan and sends the measured voltage frames through the USB serial connection.

MATLAB receives the data, displays the measurement, assigns the current gesture label, and stores the valid measurements in CSV format.

---

## Wireless HC-05 Communication Workflow

```text
MATLAB GUI
    ↓
HC-05 Bluetooth Serial Connection
    ↓
Arduino Uno
    ↓
EIT Measurement Hardware
    ↓
Voltage Frames
    ↓
MATLAB
    ↓
CSV Dataset
```

The wireless implementation replaces the direct USB communication path with an HC-05 Bluetooth serial connection.

A Python scanner is used to detect the COM port assigned to the HC-05 module.

---

## Wireless Data Collection Workflow

```text
Start MATLAB GUI
        ↓
Scan for HC-05 COM Port
        ↓
Connect to HC-05
        ↓
Select EIT Scan Type
        ↓
Confirm Scan Type
        ↓
Display Gesture Image
        ↓
User Performs Gesture
        ↓
Start Recording
        ↓
Arduino Performs EIT Scan
        ↓
Arduino Sends Measurement Frames
        ↓
MATLAB Validates Frames
        ↓
MATLAB Displays Live Data
        ↓
Save Valid Frames to CSV
        ↓
Load Next Gesture
```

Recording is enabled only after the Arduino confirms the selected scan type.

---

## EIT Scan Types

The system supports four EIT measurement configurations.

| Type | Pattern | Values per Frame |
|---|---|---:|
| Type 1 | Adjacent | 40 |
| Type 2 | Opposite | 16 |
| Type 3 | Skip-1 | 32 |
| Type 4 | Rotating Radial | 120 |

Each scan type is stored separately so that measurements from different electrode configurations are not mixed.

---

## Communication Protocol

The MATLAB-Arduino communication uses serial commands.

| Command | Direction | Purpose |
|---|---|---|
| `HELLO` | MATLAB/Python → Arduino | Check communication |
| `TYPE,1` to `TYPE,4` | MATLAB → Arduino | Select EIT scan type |
| `TYPE_SET,x` | Arduino → MATLAB | Confirm selected scan type |
| `N` | MATLAB → Arduino | Start recording |
| Measurement frame | Arduino → MATLAB | Send EIT voltage data |
| `END` | Arduino → MATLAB | Recording complete |
| `RESET` | MATLAB → Arduino | Reset the system state |

The MATLAB Start button should remain disabled until the correct `TYPE_SET,x` confirmation is received.

---

## Data Acquisition

For each gesture recording, the Arduino sends 12 measurement frames.

The first two frames are ignored because they may contain unstable measurements caused by multiplexer switching and signal settling.

```text
Frame 1      → Ignored
Frame 2      → Ignored
Frames 3–12  → Saved
```

Therefore:

```text
1 gesture recording = 10 valid measurement rows
```

---

## CSV Data Format

Each complete Arduino measurement frame becomes one horizontal CSV row.

For example, Type 2 contains 16 readings:

```text
R1,R2,R3,...,R16,GestureName
```

Separate CSV files are maintained for each EIT scan type.

Example filenames:

```text
dataset_Type1_Adjacent.csv
dataset_Type2_Opposite.csv
dataset_Type3_Skip1.csv
dataset_Type4_RR.csv
```

The gesture shown in the MATLAB interface is automatically used as the label for the recorded measurement.

---

## MATLAB GUI

The MATLAB interface provides controls for:

- HC-05 scanning
- connection and disconnection
- EIT scan-type selection
- scan-type confirmation
- gesture visualization
- recording control
- live voltage plotting
- selected-channel plotting
- CSV file storage
- automatic gesture progression

The interface also prevents recording if the Arduino has not confirmed the selected scan type.

---

## HC-05 Port Scanner

The wireless implementation includes a Python scanner located in:

```text
wireless/HC05Scanner/
```

The scanner searches the available serial ports and identifies the HC-05 communication port.

The detected COM port may be stored locally in:

```text
last_hc05_port.txt
```

This file is excluded from Git because the COM-port number can be different on each computer.

---

## Hardware Requirements

The system uses:

- Arduino Uno
- HC-05 Bluetooth module
- Electrical Impedance Tomography measurement system
- Measurement electrodes
- Power supply
- Computer running MATLAB

---

## Software Requirements

Recommended software:

- MATLAB
- Arduino IDE
- Python 3
- Python serial communication package
- Windows Bluetooth and serial-port support

---

## Running the Wireless Version

1. Power the Arduino and EIT measurement hardware.
2. Pair the HC-05 Bluetooth module with the computer.
3. Open MATLAB.
4. Run the wireless MATLAB GUI.
5. Scan for the HC-05 COM port.
6. Connect to the detected HC-05 port.
7. Select the required EIT scan type.
8. Wait for the `TYPE_SET,x` confirmation.
9. Display the required gesture.
10. Perform the gesture shown in MATLAB.
11. Start the recording.
12. Arduino performs the selected EIT measurement.
13. Arduino sends the measurement frames to MATLAB.
14. MATLAB ignores the first two frames.
15. MATLAB saves frames 3 to 12.
16. MATLAB labels the data using the currently displayed gesture.
17. Continue with the next gesture.

---

## Running the USB Version

1. Connect the Arduino to the computer using USB.
2. Power the EIT measurement system.
3. Open MATLAB.
4. Run the USB MATLAB interface.
5. Establish the serial connection.
6. Select the required EIT scan configuration.
7. Display the required gesture.
8. Perform the gesture.
9. Start the recording.
10. Arduino performs the EIT scan.
11. Measurement frames are transmitted through USB serial communication.
12. MATLAB receives and validates the frames.
13. MATLAB labels and saves the valid data to CSV.

---

## Troubleshooting

### HC-05 Not Found

Possible causes:

- HC-05 is not paired with Windows
- incorrect COM port
- Bluetooth connection is not active

Possible solution:

- pair the HC-05 module with Windows
- run the Python HC-05 scanner again
- verify the detected COM port

---

### Waiting for Type Confirmation

If MATLAB is waiting for `TYPE_SET,x`, the Arduino has not yet confirmed the selected EIT scan type.

Recording should not begin until the correct confirmation is received.

---

### Wrong Number of Values

Example:

```text
Expected 16 values but received 40
```

This can occur if MATLAB selected Type 2 while Arduino is still configured for Type 1.

Set the scan type again and wait for the correct `TYPE_SET,x` confirmation before starting acquisition.

---

### Changing Type During Recording

The EIT scan type should not be changed while Arduino is actively recording.

Wait until the current measurement is completed before selecting another scan type.

---

### Readings Without Connected Electrodes

If the measurement circuit or electrodes are not connected, the analog input may float and produce noisy readings.

Connect the measurement circuit and electrodes before collecting the final dataset.

---

## Project Documentation

Detailed documentation is available inside `docs/`.

The documentation contains:

- system overview
- software flowchart
- MATLAB initialization and connection flow
- recording and CSV processing flow
- hardware architecture
- MATLAB GUI screenshots
- testing and troubleshooting
- description of project files

---

## Gesture Images

The `gestures/` folder contains the gesture images displayed by the MATLAB GUI.

Example:

```text
gestures/
├── A_sign.png
├── B_sign.png
├── C_sign.png
└── ...
```

The currently displayed gesture image is used as the label for the acquired measurement data.

---

## Sample Data

A small example dataset can be stored in `sample-data/`.

Large experimental datasets are not included in the repository by default.

---

## Project Files

The repository contains:

- Arduino firmware for EIT measurement control
- MATLAB GUI for wired USB acquisition
- MATLAB GUI for wireless acquisition
- Python HC-05 COM-port scanner
- gesture images
- example CSV data
- project documentation

---

## Contributors

- Karan Ganesh Mahadik
- Shreya Rajendra Desai
- Jyothilakshmi Mohan

Project Lab Embedded Systems  
Chair of Measurement and Sensor Technology  
Technische Universität Chemnitz

---

## Future Work

The collected EIT gesture data can be used for further work such as:

- gesture classification
- signal processing
- feature extraction
- machine learning
- pattern recognition
- real-time gesture recognition

---

## Acknowledgement

This project was carried out as part of the Project Lab Embedded Systems at the Chair of Measurement and Sensor Technology, Technische Universität Chemnitz.

---

## License

This repository is intended for academic and educational purposes.
