/*
  Arduino EIT data sender for MATLAB gesture collection
  HC-05 moved from pins 0/1 to A2/A3 using SoftwareSerial.

  Wiring:
  HC-05 TX -> Arduino A2  (Arduino SoftwareSerial RX)
  HC-05 RX -> Arduino A3  (Arduino SoftwareSerial TX through voltage divider)
  HC-05 GND -> Arduino GND
  HC-05 VCC -> suitable HC-05 module supply

  MATLAB/Python must use BT_BAUD = 38400.
  USB Serial is kept only for debugging/uploading.
*/

#include <SoftwareSerial.h>

// ========= Bluetooth pins =========
// A2 and A3 are used as digital pins for SoftwareSerial.
const byte BT_RX_PIN = A2;  // Arduino receives from HC-05 TX
const byte BT_TX_PIN = A3;  // Arduino transmits to HC-05 RX through voltage divider
SoftwareSerial BT(BT_RX_PIN, BT_TX_PIN);

const long BT_BAUD  = 38400;
const long USB_BAUD = 115200;

// ========= Pin definitions =========
const int cn0 = 2, cn1 = 3, cn2 = 7;
const int co0 = 4, co1 = 5, co2 = 6;
const int vn0 = 10, vn1 = 11, vn2 = 12;
const int vo0 = 8,  vo1 = 9,  vo2 = 13;

// ========= Shared parameters =========
const int aP            = A1;
const int sN            = 60;    // ADC samples per measurement
const int cY            = 5;     // top/bottom averaging window
const int ddd           = 20;    // settling delay (ms)
const int EITiterations = 102;   // frames per trigger

float  answer = 0.0;
String valString;

byte selectedType = 1;
bool isRecording = false;
bool stopRequested = false;

char btCommand[40];
byte btIndex = 0;

char usbCommand[40];
byte usbIndex = 0;

// ========= Forward declarations =========
void controlCurrentMux(int, int);
void controlVoltageMux(int, int);
float voltageMeasurement(int, int, int);
void setP8();

void setup() {
  int outputs[] = {cn0,cn1,cn2, co0,co1,co2, vn0,vn1,vn2, vo0,vo1,vo2};

  for (int i = 0; i < 12; i++) {
    pinMode(outputs[i], OUTPUT);
    digitalWrite(outputs[i], LOW);
  }

  setP8();

  Serial.begin(USB_BAUD);  // USB debug only
  BT.begin(BT_BAUD);       // HC-05 communication with MATLAB

  delay(500);

  Serial.println(F("READY_USB"));
  BT.println(F("READY_HC05"));
}

void loop() {
  if (readCommandFromPort(BT, btCommand, btIndex, sizeof(btCommand))) {
    handleCommand(btCommand, true);
  }

  if (readCommandFromPort(Serial, usbCommand, usbIndex, sizeof(usbCommand))) {
    handleCommand(usbCommand, false);
  }
}

// ========= Command handling =========
bool readCommandFromPort(Stream &port, char *buffer, byte &index, byte maxLen) {
  while (port.available() > 0) {
    char c = port.read();

    if (c == '\r') continue;

    if (c == '\n') {
      buffer[index] = '\0';
      index = 0;
      trimCommand(buffer);
      return strlen(buffer) > 0;
    }

    if (index < maxLen - 1) {
      buffer[index++] = c;
    } else {
      index = 0;
      buffer[0] = '\0';
    }
  }

  return false;
}

void trimCommand(char *cmd) {
  byte start = 0;

  while (cmd[start] == ' ' || cmd[start] == '\t') start++;

  if (start > 0) {
    byte i = 0;
    while (cmd[start] != '\0') cmd[i++] = cmd[start++];
    cmd[i] = '\0';
  }

  int len = strlen(cmd);
  while (len > 0 && (cmd[len - 1] == ' ' || cmd[len - 1] == '\t')) {
    cmd[len - 1] = '\0';
    len--;
  }
}

void handleCommand(char *cmd, bool fromBluetooth) {
  Stream *out = fromBluetooth ? (Stream *)&BT : (Stream *)&Serial;

  if (strcmp(cmd, "HELLO") == 0) {
    if (fromBluetooth) {
      out->println(F("HC05_GESTURE_DEVICE"));
    } else {
      out->println(F("USB_PORT_IGNORE"));
    }
    return;
  }

  if (strcmp(cmd, "PING") == 0) {
    out->println(fromBluetooth ? F("PONG_HC05") : F("PONG_USB"));
    return;
  }

  if (strncmp(cmd, "TYPE,", 5) == 0) {
    if (isRecording) {
      out->println(F("ERROR,CANNOT_CHANGE_TYPE_WHILE_RECORDING"));
      return;
    }

    int newType = atoi(cmd + 5);

    if (newType >= 1 && newType <= 4) {
      selectedType = (byte)newType;
      out->print(F("TYPE_SET,"));
      out->println(selectedType);
    } else {
      out->println(F("ERROR,INVALID_TYPE"));
    }

    return;
  }

  if (strcmp(cmd, "N") == 0 || strcmp(cmd, "START") == 0) {
    if (isRecording) {
      out->println(F("ERROR,ALREADY_RECORDING"));
      return;
    }

    stopRequested = false;
    runSelectedType();
    return;
  }

  if (strcmp(cmd, "STOP") == 0) {
    stopRequested = true;
    out->println(F("STOP_REQUESTED"));
    return;
  }

  if (strcmp(cmd, "RESET") == 0) {
    stopRequested = true;
    isRecording = false;
    selectedType = 1;
    out->println(F("RESET_DONE"));
    return;
  }

  if (strcmp(cmd, "STATUS") == 0) {
    out->print(F("STATUS,TYPE,"));
    out->print(selectedType);
    out->print(F(",RECORDING,"));
    out->println(isRecording ? F("YES") : F("NO"));
    return;
  }

  // Backward-compatible direct trigger over USB/Bluetooth.
  if (strlen(cmd) == 1 && cmd[0] >= '1' && cmd[0] <= '4') {
    if (isRecording) {
      out->println(F("ERROR,ALREADY_RECORDING"));
      return;
    }

    selectedType = (byte)(cmd[0] - '0');
    out->print(F("TYPE_SET,"));
    out->println(selectedType);
    stopRequested = false;
    runSelectedType();
    return;
  }

  if (strncmp(cmd, "JUMP,", 5) == 0) {
    out->println(F("JUMP_ACK"));
    return;
  }

  out->print(F("ERROR,UNKNOWN_COMMAND,"));
  out->println(cmd);
}

void runSelectedType() {
  isRecording = true;

  BT.print(F("START,TYPE,"));
  BT.println(selectedType);
  Serial.print(F("START,TYPE,"));
  Serial.println(selectedType);

  for (int k = 0; k < EITiterations; k++) {
    checkStopDuringRecording();

    if (stopRequested) {
      BT.println(F("STOPPED"));
      Serial.println(F("STOPPED"));
      isRecording = false;
      return;
    }

    if      (selectedType == 1) runAdjacent();
    else if (selectedType == 2) runOpposite();
    else if (selectedType == 3) runSkip1();
    else if (selectedType == 4) runRR();
  }

  BT.println(F("END"));
  Serial.println(F("END"));
  isRecording = false;
}

void checkStopDuringRecording() {
  if (readCommandFromPort(BT, btCommand, btIndex, sizeof(btCommand))) {
    if (strcmp(btCommand, "STOP") == 0 || strcmp(btCommand, "RESET") == 0) {
      stopRequested = true;
    } else if (strncmp(btCommand, "TYPE,", 5) == 0) {
      BT.println(F("ERROR,CANNOT_CHANGE_TYPE_WHILE_RECORDING"));
    } else if (strcmp(btCommand, "HELLO") == 0) {
      BT.println(F("HC05_GESTURE_DEVICE"));
    }
  }

  if (readCommandFromPort(Serial, usbCommand, usbIndex, sizeof(usbCommand))) {
    if (strcmp(usbCommand, "STOP") == 0 || strcmp(usbCommand, "RESET") == 0) {
      stopRequested = true;
    } else if (strcmp(usbCommand, "HELLO") == 0) {
      Serial.println(F("USB_PORT_IGNORE"));
    }
  }
}

// ========= Helpers =========
void measureAndAppend(int vIn, int vOut) {
  controlVoltageMux(vIn, vOut);
  delay(ddd);

  answer = voltageMeasurement(aP, sN, cY);

  char tempStr[10];
  dtostrf(answer, 6, 4, tempStr);

  valString += String(",");
  valString += String(tempStr);
}

void emitFrame() {
  valString.remove(0, 1);
  valString += String(",");

  // Send frame to HC-05/MATLAB.
  BT.println(valString);
  BT.flush();

  // Optional USB debug copy.
  Serial.println(valString);
}

// ========= Adjacent: offset = 1, 8 injections x 5 measurements = 40 =========
void runAdjacent() {
  valString = String("");

  for (int i = 0; i < 8; i++) {
    controlCurrentMux(i, (i + 1) % 8);

    int s1 = (i + 7) % 8;
    int s2 = i;
    int s3 = (i + 1) % 8;

    for (int j = 0; j < 8; j++) {
      if (j == s1 || j == s2 || j == s3) continue;
      measureAndAppend(j, (j + 1) % 8);
    }
  }

  emitFrame();
}

// ========= Opposite: offset = 4, 4 injections x 4 measurements = 16 =========
void runOpposite() {
  valString = String("");

  for (int i = 0; i < 4; i++) {
    controlCurrentMux(i, i + 4);

    int s1 = (i + 7) % 8;
    int s2 = i;
    int s3 = (i + 3) % 8;
    int s4 = (i + 4) % 8;

    for (int j = 0; j < 8; j++) {
      if (j == s1 || j == s2 || j == s3 || j == s4) continue;
      measureAndAppend(j, (j + 1) % 8);
    }
  }

  emitFrame();
}

// ========= Skip1: offset = 2, 8 injections x 4 measurements = 32 =========
void runSkip1() {
  valString = String("");

  for (int i = 0; i < 8; i++) {
    controlCurrentMux(i, (i + 2) % 8);

    int s1 = (i + 7) % 8;
    int s2 = i;
    int s3 = (i + 1) % 8;
    int s4 = (i + 2) % 8;

    for (int j = 0; j < 8; j++) {
      if (j == s1 || j == s2 || j == s3 || j == s4) continue;
      measureAndAppend(j, (j + 1) % 8);
    }
  }

  emitFrame();
}

// ========= RR: 28 injections, 120 measurements =========
void runRR() {
  valString = String("");

  for (int focal = 0; focal < 7; focal++) {
    for (int target = focal + 1; target < 8; target++) {
      controlCurrentMux(focal, target);

      for (int j = 0; j < 8; j++) {
        int jNext = (j + 1) % 8;

        if (j == focal || j == target || jNext == focal || jNext == target) continue;

        measureAndAppend(j, jNext);
      }
    }
  }

  emitFrame();
}

// ========= Mux control =========
void controlCurrentMux(int currentInChannel, int currentOutChannel) {
  int cnPin[] = {cn0, cn1, cn2};
  int coPin[] = {co0, co1, co2};

  int cnChannel[8][3] = {
    {1,1,1},{0,1,1},{1,0,1},{0,0,1},
    {1,1,0},{0,1,0},{1,0,0},{0,0,0}
  };

  int coChannel[8][3] = {
    {0,0,0},{1,0,0},{0,1,0},{1,1,0},
    {0,0,1},{1,0,1},{0,1,1},{1,1,1}
  };

  for (int i = 0; i < 3; i++) digitalWrite(cnPin[i], cnChannel[currentInChannel][i]);
  for (int i = 0; i < 3; i++) digitalWrite(coPin[i], coChannel[currentOutChannel][i]);
}

void controlVoltageMux(int voltageInChannel, int voltageOutChannel) {
  int vnPin[] = {vn0, vn1, vn2};
  int voPin[] = {vo0, vo1, vo2};

  int vnChannel[8][3] = {
    {0,0,0},{1,0,0},{0,1,0},{1,1,0},
    {0,0,1},{1,0,1},{0,1,1},{1,1,1}
  };

  int voChannel[8][3] = {
    {1,1,1},{0,1,1},{1,0,1},{0,0,1},
    {1,1,0},{0,1,0},{1,0,0},{0,0,0}
  };

  for (int i = 0; i < 3; i++) digitalWrite(vnPin[i], vnChannel[voltageInChannel][i]);
  for (int i = 0; i < 3; i++) digitalWrite(voPin[i], voChannel[voltageOutChannel][i]);
}

// ========= Voltage measurement =========
float voltageMeasurement(int pin, int n, int cont) {
  int adcValueList[n];
  int temp = 0;
  float maxAdc = 0.0;
  float minAdc = 0.0;

  for (int i = 0; i < n; i++) {
    adcValueList[i] = analogRead(pin);
  }

  for (int i = 0; i < n; i++) {
    for (int j = i + 1; j < n; j++) {
      if (adcValueList[i] > adcValueList[j]) {
        temp = adcValueList[i];
        adcValueList[i] = adcValueList[j];
        adcValueList[j] = temp;
      }
    }
  }

  for (int i = n - cont; i < n; i++) maxAdc += adcValueList[i];
  for (int i = 0; i < cont; i++)     minAdc += adcValueList[i];

  return 5.0 * maxAdc / cont / 1023.0 - 5.0 * minAdc / cont / 1023.0;
}

// ========= ADC prescaler =========
void setP16() {
  ADCSRA |=  (1 << ADPS2);
  ADCSRA &= ~(1 << ADPS1);
  ADCSRA &= ~(1 << ADPS0);
}

void setP8() {
  ADCSRA &= ~(1 << ADPS2);
  ADCSRA |=  (1 << ADPS1);
  ADCSRA |=  (1 << ADPS0);
}
