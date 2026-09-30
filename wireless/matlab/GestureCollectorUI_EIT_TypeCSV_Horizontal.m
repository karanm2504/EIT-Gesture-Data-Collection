function GestureCollectorUI_EIT_FrameParser_A2A3_TypeCSV_Horizontal
% GestureCollectorUI_Final_GreyBlueUI
% MATLAB UI for gesture data collection using Arduino + HC-05.
%
% REAL PROJECT LOGIC:
%   1. MATLAB shows a gesture image, e.g. A.
%   2. User makes that gesture.
%   3. User clicks Start.
%   4. Arduino sends ONLY calculated readings, e.g. DATA,0.523
%   5. MATLAB labels the readings using the gesture currently shown on screen.
%   6. MATLAB decides Iteration and SampleNumber by counting readings.
%
% Expected recording per gesture/type:
%   Arduino sends 12 frames. MATLAB ignores first 2 frames.
%   CSV saves only frames 3 to 12 as 10 horizontal rows.
%
% CSV columns:
%   R1, R2, R3, ... Rn, GestureName
%
% Separate CSV files are used for each type.
% Example:
%   gesture_dataset_Type1_Adjacent.csv
%   gesture_dataset_Type2_Opposite.csv
%
%
% HC-05 SOFTWARE SERIAL NOTE:
%   Arduino HC-05 is expected on A2/A3 using SoftwareSerial.
%   MATLAB communication format is unchanged: HELLO, TYPE,x, N, DATA,value.
%   If the scanner selects Arduino USB instead of Bluetooth, disconnect USB data
%   after uploading or power Arduino externally while using HC-05.
%
% Change these paths if needed:
%   imageFolder = "D:\data\gestures";
%   saveFolder    = "D:\data\CSV";
%   comPortFolder = "D:\data\HC05Scanner";

clc;

%% ===================== SETTINGS =====================
baudRate = 38400;        % Must match Arduino HC-05 baud rate

imageFolder = "D:\data\gestures";
saveFolder  = "D:\data\CSV";

% Folder used only for storing the detected HC-05 COM port text file.
% This keeps the COM-port helper file separate from the dataset CSV files.
comPortFolder = "D:\data\HC05Scanner";

if ~isfolder(saveFolder)
    mkdir(saveFolder);
end

if ~isfolder(comPortFolder)
    mkdir(comPortFolder);
end

lastPortFile = fullfile(comPortFolder, "last_hc05_port.txt");

% 25 gestures used in your project
gestureNames = ["A", "B", "C", "D", "E", ...
                "F", "G", "H", "I", "K", ...
                "L", "M", "N", "O", "P", ...
                "Q", "R", "SCH", "S", "T", ...
                "U", "V", "W", "X", "Y"];

NUM_GESTURES = numel(gestureNames);

% Real Arduino EIT scan types:
% Type 1 = Adjacent scan       -> 40 values per frame
% Type 2 = Opposite scan       -> 16 values per frame
% Type 3 = Skip-1 scan         -> 32 values per frame
% Type 4 = Rotating radial RR  -> 120 values per frame
NUM_TYPES = 4;
EIT_ITERATIONS = 12;
GARBAGE_FRAMES = 2;
SAVED_ITERATIONS = EIT_ITERATIONS - GARBAGE_FRAMES;
VALUES_PER_TYPE = [40 16 32 120];

% The expected sample count now depends on the selected scan type.
% Example: Type 1 = 10 x 40 = 400 saved readings per gesture.
TOTAL_EXPECTED_SAMPLES = NUM_GESTURES * SAVED_ITERATIONS * sum(VALUES_PER_TYPE);

autoLoadNextImage = true;
autoNextDelaySeconds = 0.5;

%% ===================== STATE VARIABLES =====================
sp = [];
selectedPort = "";
selectedDataType = 1;
typeConfirmedForArduino = false;   % Start is allowed only after Arduino confirms TYPE_SET

isConnected = false;
isRecording = false;
ignoreIncomingData = false;

uiGestureIndex = 1;
currentGestureNumber = 0;
currentGestureName = "";
currentGestureSampleCounter = 0;
currentFrameCounter = 0;

% Holds only the latest saved readings for the currently recording gesture/type
latestRecordingData = emptyDataTable();

% Holds current session data for live plotting
allData = emptyDataTable();

selectedCsvBaseName = "gesture_dataset";
selectedCsvName = "gesture_dataset_Type1_Adjacent.csv";
selectedCsvPath = fullfile(saveFolder, selectedCsvName);

%% ===================== MAIN UI =====================
fig = uifigure("Name", "Gesture EIT Data Collector - UI Based Labels", ...
               "Position", [80 80 1320 820]);
fig.CloseRequestFcn = @closeApp;

mainGrid = uigridlayout(fig, [2 3]);
mainGrid.RowHeight = {'1x', 120};
mainGrid.ColumnWidth = {320, '1x', 360};
mainGrid.Padding = [10 10 10 10];
mainGrid.RowSpacing = 10;
mainGrid.ColumnSpacing = 10;

%% ===================== LEFT CONTROLS PANEL =====================
controlPanel = uipanel(mainGrid, "Title", "Controls");
controlPanel.Layout.Row = 1;
controlPanel.Layout.Column = 1;
try
    controlPanel.Scrollable = "on";
catch
end

controlGrid = uigridlayout(controlPanel, [32 1]);
% Polished left-side layout with more consistent button and section sizing.
% CSV settings are kept above the jump section and the whole panel remains scrollable.
controlGrid.RowHeight = {42, 42, 42, 40, 8, ...
                         24, 90, 42, 10, ...
                         52, 10, ...
                         24, 36, 42, 30, 10, ...
                         24, 110, 42, 10, ...
                         42, 42, 14, ...
                         32, 32, 32, 32, 32, 32, 32, ...
                         180, '1x'};
controlGrid.Padding = [12 12 12 12];
controlGrid.RowSpacing = 6;

% Make the entire Controls area scrollable.
% Some MATLAB versions scroll the uipanel, while others scroll the grid layout,
% so both are enabled safely.
try
    controlGrid.Scrollable = "on";
catch
end

scanBtn = uibutton(controlGrid, "Text", "Scan HC-05", ...
    "FontSize", 13, "FontWeight", "bold", ...
    "ButtonPushedFcn", @scanHC05ButtonPushed);

connectBtn = uibutton(controlGrid, "Text", "Connect HC-05", ...
    "FontSize", 13, "FontWeight", "bold", ...
    "ButtonPushedFcn", @connectHC05);

disconnectBtn = uibutton(controlGrid, "Text", "Disconnect", ...
    "FontSize", 13, "FontWeight", "bold", ...
    "ButtonPushedFcn", @disconnectHC05, "Enable", "off");

advancedBtn = uibutton(controlGrid, "Text", "Advanced Settings", ...
    "FontSize", 13, "FontWeight", "bold", ...
    "ButtonPushedFcn", @advancedSettingsButtonPushed);

uilabel(controlGrid, "Text", "");

typeLabel = uilabel(controlGrid, "Text", "Arduino EIT scan type:", ...
    "FontWeight", "bold");
typeList = createListBox(controlGrid, {"Type 1 - Adjacent (40 values)", "Type 2 - Opposite (16 values)", "Type 3 - Skip1 (32 values)", "Type 4 - RR (120 values)"}, "Type 1 - Adjacent (40 values)", @dataTypeChanged);

setTypeBtn = uibutton(controlGrid, "Text", "Set Data Type", ...
    "FontSize", 13, "FontWeight", "bold", ...
    "ButtonPushedFcn", @setDataTypeButtonPushed);

uilabel(controlGrid, "Text", "");

startBtn = uibutton(controlGrid, "Text", "Start", ...
    "FontSize", 14, "FontWeight", "bold", ...
    "ButtonPushedFcn", @startGesture, "Enable", "off");

uilabel(controlGrid, "Text", "");

% CSV settings are kept directly after Start so they are always easy to reach.
csvNameLabel = uilabel(controlGrid, "Text", "CSV base name:", ...
    "FontWeight", "bold");
csvNameField = uieditfield(controlGrid, "text", ...
    "Value", selectedCsvBaseName);

setCsvBtn = uibutton(controlGrid, "Text", "Set CSV Base Name", ...
    "FontSize", 13, "FontWeight", "bold", ...
    "ButtonPushedFcn", @setCSVNameButtonPushed);

autoSaveCheck = uicheckbox(controlGrid, "Text", "Auto-save to selected type CSV", ...
    "Value", true);

uilabel(controlGrid, "Text", "");

jumpLabel = uilabel(controlGrid, "Text", "Jump to gesture:", ...
    "FontWeight", "bold");
jumpItems = makeGestureJumpItems();
jumpList = createListBox(controlGrid, cellstr(jumpItems), char(jumpItems(1)), []);

jumpBtn = uibutton(controlGrid, "Text", "Jump to Selected Gesture", ...
    "FontSize", 13, "FontWeight", "bold", ...
    "ButtonPushedFcn", @jumpToSelectedGesture);

uilabel(controlGrid, "Text", "");

clearSessionBtn = uibutton(controlGrid, "Text", "Clear MATLAB Memory", ...
    "FontSize", 13, "ButtonPushedFcn", @clearMATLABMemory);

resetBtn = uibutton(controlGrid, "Text", "Reset Arduino + UI", ...
    "FontSize", 13, "ButtonPushedFcn", @resetArduinoAndUI);

connectionInfoLabel = uilabel(controlGrid, "Text", "Device: Not connected", ...
    "FontWeight", "bold");
csvFileInfoLabel = uilabel(controlGrid, "Text", "CSV file: " + selectedCsvName);
csvFolderInfoLabel = uilabel(controlGrid, "Text", "CSV folder: " + saveFolder);
totalInfoLabel = uilabel(controlGrid, "Text", string(NUM_GESTURES) + " gestures");
currentGestureInfoLabel = uilabel(controlGrid, ...
    "Text", "Current gesture: 1 / " + string(NUM_GESTURES) + " - A", ...
    "FontWeight", "bold");
recordInfoLabel = uilabel(controlGrid, "Text", "12 frames; first 2 ignored");
lastPortLabel = uilabel(controlGrid, "Text", "Last port: none");
modeInfoLabel = uilabel(controlGrid, "Text", "CSV: one file per selected type");

bottomSpacerLabel = uilabel(controlGrid, "Text", "");

%% ===================== MIDDLE DATA PANEL =====================
dataPanel = uipanel(mainGrid, "Title", "Live Data");
dataPanel.Layout.Row = 1;
dataPanel.Layout.Column = 2;

dataGrid = uigridlayout(dataPanel, [3 1]);
dataGrid.RowHeight = {'1x', 42, '1x'};
dataGrid.Padding = [10 10 10 10];

voltageAx = uiaxes(dataGrid);
title(voltageAx, "Live Voltage Plot");
xlabel(voltageAx, "Sample Number / Channel Number");
ylabel(voltageAx, "Voltage (V)");
grid(voltageAx, "on");

channelGrid = uigridlayout(dataGrid, [1 3]);
channelGrid.ColumnWidth = {145, 150, '1x'};
channelGrid.Padding = [0 0 0 0];

channelLabel = uilabel(channelGrid, "Text", "View channel:", ...
    "FontWeight", "bold");
channelItems = cellstr("Channel " + string(1:max(VALUES_PER_TYPE)));
channelList = createListBox(channelGrid, channelItems, "Channel 1", @channelSelectionChanged);
try
    channelList.Layout.Row = 1;
    channelList.Layout.Column = 2;
catch
end

channelInfoLabel = uilabel(channelGrid, ...
    "Text", "Select Channel 1 to 40 to compare it across 10 iterations.");
try
    channelInfoLabel.Layout.Row = 1;
    channelInfoLabel.Layout.Column = 3;
catch
end

iterationAx = uiaxes(dataGrid);
title(iterationAx, "Selected Channel Across Iterations");
xlabel(iterationAx, "Iteration Number");
ylabel(iterationAx, "Voltage (V)");
grid(iterationAx, "on");

%% ===================== RIGHT GESTURE IMAGE PANEL =====================
gesturePanel = uipanel(mainGrid, "Title", "Gesture Image");
gesturePanel.Layout.Row = 1;
gesturePanel.Layout.Column = 3;

gestureGrid = uigridlayout(gesturePanel, [8 1]);
gestureGrid.RowHeight = {30, 30, 30, '1x', 32, 32, 32, 38};
gestureGrid.Padding = [10 10 10 10];

gestureNumberLabel = uilabel(gestureGrid, ...
    "Text", "Current Gesture Number: 1", ...
    "FontSize", 14, "FontWeight", "bold");

gestureNameLabel = uilabel(gestureGrid, ...
    "Text", "Current Gesture Name: A", ...
    "FontSize", 14, "FontWeight", "bold");

sampleCountLabel = uilabel(gestureGrid, ...
    "Text", "Saved in CSV - Type 1: 0 / " + string(expectedRowsForType(selectedDataType) * NUM_GESTURES) + ...
            " | Total: 0 / " + string(TOTAL_EXPECTED_SAMPLES), ...
    "FontSize", 12);

imageAx = uiaxes(gestureGrid);
title(imageAx, "Gesture Image");
imageAx.XTick = [];
imageAx.YTick = [];
imageAx.Box = "on";

connectionLabel = uilabel(gestureGrid, ...
    "Text", "Status: Not connected", "FontSize", 13);

progressLabel = uilabel(gestureGrid, ...
    "Text", "Select COM port and connect HC-05.", "FontSize", 13);

instructionLabel = uilabel(gestureGrid, ...
    "Text", "MATLAB labels readings using the displayed gesture.", "FontSize", 12);

currentRecordLabel = uilabel(gestureGrid, ...
    "Text", "No recording active.", "FontSize", 12);

%% ===================== LOG PANEL =====================
logPanel = uipanel(mainGrid, "Title", "Log");
logPanel.Layout.Row = 2;
logPanel.Layout.Column = [1 3];

logGrid = uigridlayout(logPanel, [1 1]);
logBox = uitextarea(logGrid, "Editable", "off", "FontSize", 12);

%% ===================== STARTUP =====================
applyTheme();
loadLastPortLabel();
showCurrentGestureImage();
updateSampleCounterLabel();
appendLog("MATLAB UI started.");
appendLog("Arduino is expected to send only calculated readings: DATA,value");
appendLog("MATLAB sends TYPE,1..4 so Arduino chooses calculation method.");
appendLog("MATLAB decides gesture label, iteration, and sample number by counting readings.");
appendLog("Arduino sends 12 frames. MATLAB ignores frames 1-2 and saves frames 3-12.");
appendLog("CSV format: R1, R2, ..., Rn, GestureName. One CSV file per type.");
appendLog("CSV path: " + selectedCsvPath);
appendLog("CSV settings are placed above the Jump section.");

%% =====================================================
% CALLBACKS AND HELPER FUNCTIONS
%% =====================================================

    function scanHC05ButtonPushed(~, ~)
        if isRecording
            appendLog("Cannot scan while recording.");
            return;
        end

        scanBtn.Enable = "off";
        connectBtn.Enable = "off";
        disconnectBtn.Enable = "off";
        startBtn.Enable = "off";

        closeCurrentSerial();

        connectionInfoLabel.Text = "Device: Scanning...";
        connectionLabel.Text = "Status: Scanning HC-05...";
        progressLabel.Text = "Scanning Bluetooth COM ports...";
        appendLog("Scanning for HC-05 Bluetooth COM port...");
        drawnow;

        found = scanForHC05Port();

        scanBtn.Enable = "on";

        if found ~= ""
            selectedPort = found;
            saveLastPort(selectedPort);

            scanBtn.Enable = "on";
            connectBtn.Enable = "on";
            disconnectBtn.Enable = "off";
            startBtn.Enable = "off";

            connectionInfoLabel.Text = "Device: HC-05 found";
            connectionLabel.Text = "Status: HC-05 found on " + selectedPort;
            progressLabel.Text = "HC-05 found. Click Connect HC-05.";
            lastPortLabel.Text = "Detected port: " + selectedPort;

            appendLog("HC-05 found on " + selectedPort + ".");
            appendLog("Click Connect HC-05 to open this port.");
        else
            selectedPort = "";
            connectBtn.Enable = "on";
            disconnectBtn.Enable = "off";
            startBtn.Enable = "off";

            connectionInfoLabel.Text = "Device: HC-05 not found";
            connectionLabel.Text = "Status: Scan failed";
            progressLabel.Text = "HC-05 not found. Check pairing/power and try again.";
            lastPortLabel.Text = "Detected port: none";

            appendLog("HC-05 not found.");
            appendLog("Make sure Windows has paired HC-05 and Arduino is powered.");
            appendLog("Close Arduino Serial Monitor, PuTTY, MATLAB serial sessions, and Python scanner.");
        end
    end

    function foundPort = scanForHC05Port()
        foundPort = "";

        % Python-only scanner:
        % MATLAB will NOT open each COM port during scanning because Windows Bluetooth
        % COM ports can make MATLAB hang. Python already works well in your terminal,
        % so the MATLAB Scan button only runs Python and then reads last_hc05_port.txt.

        scannerFolder = "D:\data\HC05Scanner";
        portFile = fullfile(scannerFolder, "last_hc05_port.txt");

        scriptFast = fullfile(scannerFolder, "scan_hc05_fast.py");
        scriptNormal = fullfile(scannerFolder, "scan_hc05.py");

        if isfile(scriptFast)
            pythonScript = scriptFast;
        elseif isfile(scriptNormal)
            pythonScript = scriptNormal;
        else
            pythonScript = "";
        end

        if pythonScript == ""
            appendLog("Python scanner file not found.");
            appendLog("Expected one of these files:");
            appendLog(scriptFast);
            appendLog(scriptNormal);

            % If a previous Python scan already created the text file, use it.
            if isfile(portFile)
                detected = strtrim(string(fileread(portFile)));
                if detected ~= ""
                    foundPort = detected;
                    appendLog("Using previously saved HC-05 port: " + foundPort);
                    return;
                end
            end

            appendLog("Run Python manually once, or place scan_hc05.py in D:\data\HC05Scanner.");
            return;
        end

        appendLog("Running Python scanner:");
        appendLog(pythonScript);
        connectionLabel.Text = "Status: Running Python scanner...";
        progressLabel.Text = "Scanning HC-05 using Python. Please wait...";
        drawnow;

        % Delete old detected port before a new scan so MATLAB does not reuse a stale port.
        try
            if isfile(portFile)
                delete(portFile);
            end
        catch
        end

        % Use Python from Windows PATH. This is the same command style that works in terminal.
        cmd = "python """ + pythonScript + """";
        [status, result] = system(cmd);

        resultLines = splitlines(string(result));
        for rr = 1:numel(resultLines)
            line = strtrim(resultLines(rr));
            if line ~= ""
                appendLog(line);
            end
        end

        if status ~= 0
            appendLog("Python scanner returned an error code: " + string(status));
            appendLog("If it works in terminal, check that MATLAB is using the same Python command.");
        end

        if isfile(portFile)
            detected = strtrim(string(fileread(portFile)));
            if detected ~= ""
                foundPort = detected;
                appendLog("Python scanner detected HC-05 on " + foundPort + ".");
                return;
            end
        end

        appendLog("Python scanner did not create last_hc05_port.txt.");
        appendLog("Run this in PowerShell to test:");
        appendLog("cd /d D:\data\HC05Scanner");
        appendLog("python scan_hc05.py");
    end

    function advancedSettingsButtonPushed(~, ~)
        if isRecording
            appendLog("Cannot change COM port while recording.");
            return;
        end

        portDlg = uifigure("Name", "Advanced HC-05 COM Port Settings", ...
            "Position", [520 260 430 420]);

        portGrid = uigridlayout(portDlg, [7 1]);
        portGrid.RowHeight = {34, 32, '1x', 42, 42, 42, 28};
        portGrid.Padding = [18 16 18 16];
        portGrid.RowSpacing = 9;

        titleLabel = uilabel(portGrid, ...
            "Text", "Select HC-05 Bluetooth COM port manually", ...
            "FontSize", 15, "FontWeight", "bold");

        helpLabel = uilabel(portGrid, ...
            "Text", "Use this only if automatic Scan HC-05 does not work.");

        portsNow = getManualPortList();

        portList = uilistbox(portGrid, ...
            "Items", cellstr(portsNow(:).'), ...
            "FontSize", 13);

        if ~isempty(portsNow)
            portList.Value = char(portsNow(1));
        end

        refreshBtn = uibutton(portGrid, "Text", "Refresh COM Ports", ...
            "FontSize", 13, "FontWeight", "bold", ...
            "ButtonPushedFcn", @refreshManualPorts);

        useBtn = uibutton(portGrid, "Text", "Use Selected Port", ...
            "FontSize", 13, "FontWeight", "bold", ...
            "ButtonPushedFcn", @useManualPort);

        closeBtn = uibutton(portGrid, "Text", "Close", ...
            "FontSize", 13, ...
            "ButtonPushedFcn", @(~, ~) close(portDlg));

        statusLbl = uilabel(portGrid, ...
            "Text", "Select the outgoing HC-05 Bluetooth COM port.");

        try
            portDlg.Color = [1 1 1];
            portGrid.BackgroundColor = [1 1 1];
            titleLabel.FontColor = [0 0 0];
            helpLabel.FontColor = [0 0 0];
            statusLbl.FontColor = [0 0 0];

            portList.BackgroundColor = [1 1 1];
            portList.FontColor = [0 0 0];

            refreshBtn.BackgroundColor = [0.86 0.86 0.86];
            refreshBtn.FontColor = [0 0 0];

            useBtn.BackgroundColor = [0.10 0.40 0.80];
            useBtn.FontColor = [1 1 1];

            closeBtn.BackgroundColor = [0.86 0.86 0.86];
            closeBtn.FontColor = [0 0 0];
        catch
        end

        function portItems = getManualPortList()
            portItems = string(serialportlist("all"));
            portItems = sortPortsHighToLow(portItems);

            if isempty(portItems)
                portItems = "No COM ports found";
            end
        end

        function refreshManualPorts(~, ~)
            portItems = getManualPortList();
            portList.Items = cellstr(portItems(:).');
            portList.Value = char(portItems(1));
            statusLbl.Text = "COM ports refreshed.";
        end

        function useManualPort(~, ~)
            chosen = string(portList.Value);

            if chosen == "" || chosen == "No COM ports found"
                statusLbl.Text = "No valid COM port selected.";
                return;
            end

            if isConnected
                closeCurrentSerial();
                isConnected = false;
                disconnectBtn.Enable = "off";
                startBtn.Enable = "off";
                scanBtn.Enable = "on";
            end

            selectedPort = chosen;
            saveLastPort(selectedPort);

            lastPortLabel.Text = "Manual port: " + selectedPort;
            connectionInfoLabel.Text = "Device: Manual port selected";
            connectionLabel.Text = "Status: Manual port selected: " + selectedPort;
            progressLabel.Text = "Manual port selected. Click Connect HC-05.";

            connectBtn.Enable = "on";

            appendLog("Manual COM port selected: " + selectedPort);
            appendLog("Click Connect HC-05 to open this port.");

            close(portDlg);
        end
    end

    function connectHC05(~, ~)
        if isRecording
            appendLog("Cannot connect while recording.");
            return;
        end

        if selectedPort == ""
            if isfile(lastPortFile)
                try
                    saved = strtrim(string(fileread(lastPortFile)));
                    if saved ~= ""
                        selectedPort = saved;
                        appendLog("Using last detected port: " + selectedPort);
                    end
                catch
                    selectedPort = "";
                end
            end
        end

        if selectedPort == ""
            appendLog("No detected HC-05 port. Scanning now...");
            scanBtn.Enable = "off";
            connectBtn.Enable = "off";
            drawnow;

            selectedPort = scanForHC05Port();

            scanBtn.Enable = "on";
            connectBtn.Enable = "on";

            if selectedPort == ""
                connectionInfoLabel.Text = "Device: HC-05 not found";
                connectionLabel.Text = "Status: Scan failed";
                progressLabel.Text = "HC-05 not found. Click Scan HC-05 and try again.";
                appendLog("Connect cancelled because no HC-05 port was detected.");
                return;
            else
                saveLastPort(selectedPort);
                lastPortLabel.Text = "Detected port: " + selectedPort;
            end
        end

        portName = selectedPort;

        try
            closeCurrentSerial();

            scanBtn.Enable = "off";
            connectBtn.Enable = "off";
            disconnectBtn.Enable = "off";
            startBtn.Enable = "off";

            connectionInfoLabel.Text = "Device: Connecting...";
            connectionLabel.Text = "Status: Connecting to " + portName;
            progressLabel.Text = "Connecting to " + portName + "...";
            drawnow;

            sp = serialport(portName, baudRate, "Timeout", 0.5);
            configureTerminator(sp, "LF");
            flush(sp);
            pause(0.3);

            foundHello = false;
            try
                writeline(sp, "HELLO");
                t0 = tic;
                while toc(t0) < 2.0
                    if sp.NumBytesAvailable > 0
                        resp = strtrim(readline(sp));
                        appendLog("Arduino: " + string(resp));

                        if contains(string(resp), "HC05_GESTURE_DEVICE") || contains(string(resp), "READY")
                            foundHello = true;
                            break;
                        elseif contains(string(resp), "USB_PORT_IGNORE")
                            appendLog("Selected port is Arduino USB, not HC-05.");
                            error("USB_PORT_IGNORE received. Use HC-05 Bluetooth port.");
                        end
                    end
                    pause(0.05);
                end
            catch ME
                if contains(string(ME.message), "USB_PORT_IGNORE")
                    rethrow(ME);
                end
            end

            configureCallback(sp, "terminator", @serialCallback);

            isConnected = true;
            selectedPort = portName;
            saveLastPort(portName);

            scanBtn.Enable = "off";
            connectBtn.Enable = "off";
            disconnectBtn.Enable = "on";
            startBtn.Enable = "off";
            typeConfirmedForArduino = false;

            if foundHello
                connectionInfoLabel.Text = "Device: HC-05 connected";
                connectionLabel.Text = "Status: Connected to " + portName;
                progressLabel.Text = "Connected. Select type and click Set Data Type.";
            else
                connectionInfoLabel.Text = "Device: Connected, no HELLO reply";
                connectionLabel.Text = "Status: Connected to " + portName;
                progressLabel.Text = "Connected. Select type and click Set Data Type.";
            end

            lastPortLabel.Text = "Connected port: " + portName;
            appendLog("Connected on " + portName + " at " + string(baudRate) + " baud.");

        catch ME
            isConnected = false;
            sp = [];
            scanBtn.Enable = "on";
            connectBtn.Enable = "on";
            disconnectBtn.Enable = "off";
            startBtn.Enable = "off";
            connectionInfoLabel.Text = "Device: Not connected";
            connectionLabel.Text = "Status: Connection failed";
            progressLabel.Text = "Connection failed.";
            appendLog("Connection failed: " + ME.message);
        end
    end

    function disconnectHC05(~, ~)
        if isRecording
            appendLog("Stop/reset recording before disconnecting.");
            return;
        end
        closeCurrentSerial();
        isConnected = false;
        typeConfirmedForArduino = false;
        scanBtn.Enable = "on";
        connectBtn.Enable = "on";
        disconnectBtn.Enable = "off";
        startBtn.Enable = "off";
        connectionInfoLabel.Text = "Device: Disconnected";
        connectionLabel.Text = "Status: Disconnected";
        progressLabel.Text = "Disconnected.";
        appendLog("Disconnected.");
    end


    function n = expectedValuesForType(typeNumber)
        if typeNumber < 1 || typeNumber > numel(VALUES_PER_TYPE)
            n = VALUES_PER_TYPE(1);
        else
            n = VALUES_PER_TYPE(typeNumber);
        end
    end

    function n = expectedRowsForCurrentGestureType()
        n = SAVED_ITERATIONS * expectedValuesForType(selectedDataType);
    end

    function n = expectedRowsForType(typeNumber)
        n = SAVED_ITERATIONS * expectedValuesForType(typeNumber);
    end

    function name = scanTypeName(typeNumber)
        switch typeNumber
            case 1
                name = "Adjacent";
            case 2
                name = "Opposite";
            case 3
                name = "Skip1";
            case 4
                name = "RR";
            otherwise
                name = "Unknown";
        end
    end

    function dataTypeChanged(~, ~)
        selectedDataType = parseSelectedType();
        typeConfirmedForArduino = false;
        updateSelectedCsvForType();
        updateSampleCounterLabel();

        % User changed the method, so Arduino must be told this type again
        % before Start is allowed.
        if isConnected && ~isempty(sp) && ~isRecording
            startBtn.Enable = "off";
            progressLabel.Text = "Type " + string(selectedDataType) + ...
                " selected. Click Set Data Type before Start.";
            instructionLabel.Text = "First set Arduino calculation method, then click Start.";
        else
            progressLabel.Text = "Selected Data Type " + string(selectedDataType) + ".";
        end
    end

    function setDataTypeButtonPushed(~, ~)
        if isRecording
            appendLog("Cannot change type while recording.");
            return;
        end

        selectedDataType = parseSelectedType();
        typeConfirmedForArduino = false;
        updateSelectedCsvForType();
        updateSampleCounterLabel();

        if ~isConnected || isempty(sp)
            startBtn.Enable = "off";
            progressLabel.Text = "Connect HC-05 first, then set data type.";
            appendLog("Connect HC-05 first before setting Arduino data type.");
            return;
        end

        try
            flush(sp);
        catch
        end

        try
            writeline(sp, "TYPE," + string(selectedDataType));
            appendLog("Sent to Arduino: TYPE," + string(selectedDataType));
            progressLabel.Text = "Waiting for Arduino TYPE_SET," + string(selectedDataType) + "...";
            instructionLabel.Text = "Arduino must confirm type before Start is enabled.";
        catch ME
            startBtn.Enable = "off";
            appendLog("Could not send TYPE command: " + ME.message);
        end
    end

    function startGesture(~, ~)
        if ~isConnected || isempty(sp)
            appendLog("Connect HC-05 first.");
            return;
        end

        if isRecording
            appendLog("Already recording. Please wait.");
            return;
        end

        if uiGestureIndex < 1 || uiGestureIndex > NUM_GESTURES
            appendLog("Invalid gesture index.");
            return;
        end

        if ~typeConfirmedForArduino
            appendLog("Select a data type and click Set Data Type before Start.");
            progressLabel.Text = "Set Data Type first. Arduino must confirm TYPE_SET.";
            instructionLabel.Text = "Choose Type 1/2/3/4, click Set Data Type, then Start.";
            startBtn.Enable = "off";
            return;
        end

        try
            selectedDataType = parseSelectedType();
            updateSelectedCsvForType();

            % Horizontal CSV is used only for final storage.
            % Internal MATLAB plotting uses the temporary long table for the current recording.
            loadSelectedCSVIntoMemory(false);

            currentGestureNumber = uiGestureIndex;
            currentGestureName = gestureNames(uiGestureIndex);
            currentGestureSampleCounter = 0;
            currentFrameCounter = 0;
            latestRecordingData = emptyDataTable();

            % Remove old data for this Gesture + Type from memory only,
            % so live plots show the new recording cleanly.
            allData = removeGestureTypeRows(allData, currentGestureNumber, selectedDataType);
            updateSampleCounterLabel();

            clearGestureScreen();

            isRecording = true;
            ignoreIncomingData = false;

            startBtn.Enable = "off";
            jumpBtn.Enable = "off";
            setTypeBtn.Enable = "off";
            csvNameField.Enable = "off";
            setCsvBtn.Enable = "off";

            gestureNumberLabel.Text = "Recording Gesture Number: " + string(currentGestureNumber);
            gestureNameLabel.Text = "Recording Gesture Name: " + currentGestureName;
            updateCurrentGestureInfoLabel("Recording");
            progressLabel.Text = "Recording " + currentGestureName + " | Arduino EIT Type " + string(selectedDataType);
            instructionLabel.Text = "Frames 1-2 are ignored. Frames 3-12 are saved horizontally in the selected type CSV.";
            currentRecordLabel.Text = "Current recording: 0 / " + string(expectedRowsForCurrentGestureType()) + ...
                " saved readings | 0 / " + string(EIT_ITERATIONS) + " Arduino frames";

            appendLog("Start recording: Gesture " + string(currentGestureNumber) + ...
                      " (" + currentGestureName + "), Arduino EIT Type " + string(selectedDataType));

            % Clear any old Bluetooth lines before a new recording.
            % This prevents late/leftover DATA lines from the previous recording
            % from being counted in the new gesture.
            try
                flush(sp);
            catch
            end

            % Tell Arduino which type is selected, then start recording.
            writeline(sp, "TYPE," + string(selectedDataType));
            pause(0.05);
            writeline(sp, "N");
            appendLog("Sent to Arduino: TYPE," + string(selectedDataType));
            appendLog("Sent to Arduino: N");

        catch ME
            isRecording = false;
            if typeConfirmedForArduino
                startBtn.Enable = "on";
            else
                startBtn.Enable = "off";
            end
            jumpBtn.Enable = "on";
            setTypeBtn.Enable = "on";
            csvNameField.Enable = "on";
            setCsvBtn.Enable = "on";
            appendLog("Failed to start: " + ME.message);
        end
    end

    function jumpToSelectedGesture(~, ~)
        if isRecording
            appendLog("Cannot jump while recording.");
            return;
        end

        item = string(jumpList.Value);
        token = regexp(item, '^\s*(\d+)', 'tokens', 'once');
        if isempty(token)
            appendLog("Invalid jump selection.");
            return;
        end

        newIndex = str2double(token{1});
        if isnan(newIndex) || newIndex < 1 || newIndex > NUM_GESTURES
            appendLog("Invalid gesture number.");
            return;
        end

        uiGestureIndex = newIndex;
        currentGestureNumber = 0;
        currentGestureName = "";
        currentGestureSampleCounter = 0;
        latestRecordingData = emptyDataTable();

        showCurrentGestureImage();
        progressLabel.Text = "Jumped to gesture " + gestureNames(uiGestureIndex) + ". Click Start.";
        appendLog("Jumped to gesture " + string(uiGestureIndex) + ": " + gestureNames(uiGestureIndex));
        appendLog("Arduino does not need the gesture name. MATLAB will label the readings.");
    end

    function setCSVNameButtonPushed(~, ~)
        if isRecording
            appendLog("Cannot change CSV file while recording.");
            return;
        end

        rawName = strtrim(string(csvNameField.Value));
        if rawName == ""
            uialert(fig, "Please enter a CSV base name.", "Missing file name");
            return;
        end

        safeName = erase(string(makeSafeFileName(rawName)), ".csv");
        if strlength(safeName) == 0
            safeName = "gesture_dataset";
        end
        selectedCsvBaseName = safeName;
        selectedDataType = parseSelectedType();
        updateSelectedCsvForType();

        if isfile(selectedCsvPath)
            loadSelectedCSVIntoMemory(true);
            uialert(fig, ...
                "Type CSV already exists. Re-recording will replace only the selected gesture in this type file.", ...
                "Existing CSV file");
            appendLog("Loaded existing CSV: " + selectedCsvPath);
        else
            allData = emptyDataTable();
            latestRecordingData = emptyDataTable();
            writetable(emptyHorizontalCsvTable(selectedDataType), selectedCsvPath);
            uialert(fig, "New empty type CSV file created.", "New CSV file");
            appendLog("Created new CSV: " + selectedCsvPath);
        end

        updateSampleCounterLabel();
    end

    function clearMATLABMemory(~, ~)
        if isRecording
            appendLog("Cannot clear MATLAB memory while recording.");
            return;
        end

        allData = emptyDataTable();
        latestRecordingData = emptyDataTable();
        currentGestureSampleCounter = 0;
        currentGestureNumber = 0;
        currentGestureName = "";
        uiGestureIndex = 1;

        clearGestureScreen();
        showCurrentGestureImage();
        updateSampleCounterLabel();

        appendLog("MATLAB memory cleared. CSV file was NOT deleted.");
    end

    function resetArduinoAndUI(~, ~)
        if isRecording
            ignoreIncomingData = true;
            isRecording = false;
        end

        try
            if isConnected && ~isempty(sp)
                writeline(sp, "RESET");
                appendLog("Sent to Arduino: RESET");
            end
        catch ME
            appendLog("Could not send RESET: " + ME.message);
        end

        uiGestureIndex = 1;
        currentGestureNumber = 0;
        currentGestureName = "";
        currentGestureSampleCounter = 0;
        latestRecordingData = emptyDataTable();

        startBtn.Enable = ternary(isConnected, "on", "off");
        jumpBtn.Enable = "on";
        setTypeBtn.Enable = "on";
        csvNameField.Enable = "on";
        setCsvBtn.Enable = "on";

        clearGestureScreen();
        showCurrentGestureImage();
        progressLabel.Text = "Reset done. Current gesture is A.";
        instructionLabel.Text = "Click Start when user makes the shown gesture.";
        currentRecordLabel.Text = "No recording active.";
        appendLog("MATLAB UI reset to Gesture A.");
    end

    function serialCallback(src, ~)
        try
            line = strtrim(readline(src));
            if strlength(line) == 0
                return;
            end
            handleArduinoLine(string(line));
        catch ME
            appendLog("Serial read error: " + ME.message);
        end
    end

    function handleArduinoLine(line)
        if ignoreIncomingData
            if contains(line, "RESET_DONE") || contains(line, "STOPPED") || contains(line, "READY")
                ignoreIncomingData = false;
                appendLog("Arduino: " + line);
            end
            return;
        end

        % TYPE_SET is the important confirmation:
        % Start is enabled only after Arduino confirms the selected EIT scan type.
        if startsWith(line, "TYPE_SET")
            appendLog("Arduino: " + line);

            parts = split(line, ",");
            if numel(parts) >= 2
                confirmedType = str2double(parts(2));
            else
                confirmedType = NaN;
            end

            if ~isnan(confirmedType) && confirmedType == selectedDataType
                typeConfirmedForArduino = true;

                if isConnected && ~isRecording
                    startBtn.Enable = "on";
                end

                progressLabel.Text = "Arduino Type " + string(selectedDataType) + ...
                    " (" + scanTypeName(selectedDataType) + ") confirmed. Now click Start.";
                instructionLabel.Text = "User should make " + gestureNames(uiGestureIndex) + ...
                    ", then click Start.";
            else
                typeConfirmedForArduino = false;
                startBtn.Enable = "off";
                progressLabel.Text = "Arduino confirmed a different type. Set Data Type again.";
            end

            return;
        end

        % Real EIT Arduino output:
        % one full CSV frame line, for example:
        % 1.2345,1.3456,1.4567,...,
        [okFrame, frameValues] = extractFrameValuesFromLine(line);

        if okFrame
            processFrameReading(frameValues);
            return;
        end

        % Non-data status lines are just shown in log.
        if startsWith(line, "END") || startsWith(line, "START") || ...
           startsWith(line, "START_ITERATION") || startsWith(line, "END_ITERATION") || ...
           startsWith(line, "SET_TYPE") || startsWith(line, "RESET") || ...
           startsWith(line, "READY") || startsWith(line, "ERROR") || ...
           startsWith(line, "HC05")
            appendLog("Arduino: " + line);
        else
            appendLog("Arduino text ignored: " + line);
        end
    end

    function [okFrame, values] = extractFrameValuesFromLine(line)
        okFrame = false;
        values = [];

        s = strtrim(string(line));

        if s == "" || startsWith(s, "START") || startsWith(s, "END") || ...
           startsWith(s, "READY") || startsWith(s, "TYPE") || ...
           startsWith(s, "ERROR") || startsWith(s, "HC05") || ...
           startsWith(s, "RESET") || startsWith(s, "STOP")
            return;
        end

        parts = split(s, ",");
        parts = strtrim(parts);
        parts(parts == "") = [];

        if isempty(parts)
            return;
        end

        nums = str2double(parts);

        if any(isnan(nums))
            return;
        end

        expectedN = expectedValuesForType(selectedDataType);

        if numel(nums) ~= expectedN
            appendLog("WARNING: Expected " + string(expectedN) + ...
                " values for Type " + string(selectedDataType) + ...
                ", received " + string(numel(nums)) + ".");
        end

        values = nums(:)';
        okFrame = true;
    end

    function processFrameReading(frameValues)
        if ~isRecording
            return;
        end

        if currentFrameCounter >= EIT_ITERATIONS
            return;
        end

        currentFrameCounter = currentFrameCounter + 1;

        rowsThisFrame = numel(frameValues);

        % First 2 Arduino frames are stabilization/garbage data.
        % MATLAB receives them, counts them, and shows the status,
        % but does NOT add them to latestRecordingData, allData, or CSV.
        if currentFrameCounter <= GARBAGE_FRAMES
            currentRecordLabel.Text = "Ignoring garbage frame " + string(currentFrameCounter) + ...
                " / " + string(GARBAGE_FRAMES) + ...
                " | saved readings: " + string(currentGestureSampleCounter) + ...
                " / " + string(expectedRowsForCurrentGestureType());

            appendLog("Ignored garbage frame " + string(currentFrameCounter) + ...
                " with " + string(rowsThisFrame) + " values.");

            if currentFrameCounter >= EIT_ITERATIONS
                finishCurrentGestureRecording();
            end
            return;
        end

        % Saved iteration number starts from 1.
        % Arduino frame 3 becomes CSV row/iteration 1.
        iterationNumber = currentFrameCounter - GARBAGE_FRAMES;

        gestureNumber = currentGestureNumber;
        gestureName = currentGestureName;
        dataType = selectedDataType;

        for sampleNumber = 1:rowsThisFrame
            currentGestureSampleCounter = currentGestureSampleCounter + 1;

            voltageValue = frameValues(sampleNumber);
            timeText = string(datetime("now", "Format", "yyyy-MM-dd_HH-mm-ss.SSS"));

            newRow = table( ...
                dataType, ...
                gestureNumber, ...
                string(gestureName), ...
                iterationNumber, ...
                sampleNumber, ...
                voltageValue, ...
                timeText, ...
                'VariableNames', {'DataType', 'GestureNumber', 'GestureName', 'Iteration', 'SampleNumber', 'Voltage', 'Time'} ...
            );

            latestRecordingData = [latestRecordingData; newRow]; %#ok<AGROW>
            allData = [allData; newRow]; %#ok<AGROW>
        end

        currentRecordLabel.Text = "Current recording: " + string(currentGestureSampleCounter) + ...
            " / " + string(expectedRowsForCurrentGestureType()) + ...
            " saved readings | Arduino frame " + string(currentFrameCounter) + ...
            " / " + string(EIT_ITERATIONS) + ...
            " | CSV row " + string(iterationNumber) + " / " + string(SAVED_ITERATIONS);

        updateLivePlots(gestureNumber, dataType, iterationNumber, rowsThisFrame);
        updateSampleCounterLabel();

        if currentFrameCounter >= EIT_ITERATIONS
            finishCurrentGestureRecording();
        end
    end

    function finishCurrentGestureRecording()
        isRecording = false;

        appendLog("Finished Gesture " + string(currentGestureNumber) + ...
            " (" + currentGestureName + "), Type " + string(selectedDataType) + ...
            ". Saved readings: " + string(height(latestRecordingData)) + ...
            " / " + string(expectedRowsForCurrentGestureType()) + ...
            " after ignoring first 2 frames.");

        if height(latestRecordingData) < expectedRowsForCurrentGestureType()
            appendLog("WARNING: Recording finished with incomplete sample count.");
        end

        if autoSaveCheck.Value
            saveLatestRecordingToSelectedCSV();
        end

        startBtn.Enable = "on";
        jumpBtn.Enable = "on";
        setTypeBtn.Enable = "on";
        csvNameField.Enable = "on";
        setCsvBtn.Enable = "on";

        progressLabel.Text = "Finished " + currentGestureName + " | Type " + string(selectedDataType);
        instructionLabel.Text = "Saved. Next image will load automatically. Set type again if you change scan pattern.";
        currentRecordLabel.Text = "No recording active.";

        if autoLoadNextImage && uiGestureIndex < NUM_GESTURES
            pause(autoNextDelaySeconds);
            uiGestureIndex = uiGestureIndex + 1;
            showCurrentGestureImage();
            progressLabel.Text = "Next gesture loaded: " + gestureNames(uiGestureIndex) + ". Click Start.";
            instructionLabel.Text = "User should make the shown gesture, then click Start.";
            appendLog("Auto-loaded next gesture: " + gestureNames(uiGestureIndex));
        elseif uiGestureIndex >= NUM_GESTURES
            progressLabel.Text = "All gesture images completed for selected type.";
            instructionLabel.Text = "Use type selector or jump list if more data is needed.";
        end
    end

    function saveLatestRecordingToSelectedCSV()
        if height(latestRecordingData) == 0
            appendLog("No latest recording data to save.");
            return;
        end

        gName = string(latestRecordingData.GestureName(1));
        dType = double(latestRecordingData.DataType(1));
        updateSelectedCsvForType();

        try
            if isfile(selectedCsvPath)
                diskData = readtable(selectedCsvPath, "TextType", "string");
                diskData = normalizeHorizontalCsvTable(diskData, dType);
            else
                diskData = emptyHorizontalCsvTable(dType);
            end

            % Replace ONLY this gesture inside the selected type CSV.
            if height(diskData) > 0 && ismember("GestureName", string(diskData.Properties.VariableNames))
                diskData(string(diskData.GestureName) == gName, :) = [];
            end

            horizontalRows = horizontalTableForLatestRecording(dType);
            finalData = [diskData; horizontalRows];

            writetable(finalData, selectedCsvPath);

            appendLog("CSV updated: replaced Gesture " + gName + ...
                " in Type " + string(dType) + " CSV only.");
            appendLog("Saved to: " + selectedCsvPath);
            updateSampleCounterLabel();
        catch ME
            appendLog("CSV save failed: " + ME.message);
            uialert(fig, "CSV save failed: " + ME.message, "Save error");
        end
    end

    function loadSelectedCSVIntoMemory(showMessage)
        if nargin < 1
            showMessage = false;
        end

        % New CSV files are horizontal and are used only for storage.
        % Internal live plots use allData from the current MATLAB recording only.
        allData = emptyDataTable();

        if isfile(selectedCsvPath)
            try
                loaded = readtable(selectedCsvPath, "TextType", "string");
                if showMessage
                    appendLog("Loaded horizontal type CSV rows: " + string(height(loaded)));
                end
            catch ME
                appendLog("Could not inspect CSV. Starting with empty memory. Error: " + ME.message);
            end
        end
        updateSampleCounterLabel();
    end

    function updateLivePlots(gestureNumber, dataType, iterationNumber, sampleNumber)
        try
            idx = allData.GestureNumber == gestureNumber & ...
                  allData.DataType == dataType & ...
                  allData.Iteration == iterationNumber;

            plotData = allData(idx, :);
            plotData = sortrows(plotData, "SampleNumber");

            plot(voltageAx, plotData.SampleNumber, plotData.Voltage, "-o");
            title(voltageAx, "Gesture " + gestureNames(gestureNumber) + ...
                " | Type " + string(dataType) + ...
                " | Iteration " + string(iterationNumber));
            xlabel(voltageAx, "Sample Number / Channel Number");
            ylabel(voltageAx, "Voltage (V)");
            voltageAx.XLim = [1 expectedValuesForType(dataType)];
            grid(voltageAx, "on");

            updateChannelAcrossIterationsPlot();
            drawnow limitrate;
        catch ME
            appendLog("Plot update error: " + ME.message);
        end
    end

    function channelSelectionChanged(~, ~)
        updateChannelAcrossIterationsPlot();
    end

    function updateChannelAcrossIterationsPlot()
        try
            if height(allData) == 0
                clearIterationAxis();
                channelInfoLabel.Text = "No data received yet.";
                return;
            end

            selectedText = string(channelList.Value);
            sampleNo = str2double(extractAfter(selectedText, "Channel "));
            if isnan(sampleNo)
                sampleNo = 1;
            end

            if currentGestureNumber > 0
                gNum = currentGestureNumber;
                gName = currentGestureName;
            else
                gNum = uiGestureIndex;
                gName = gestureNames(uiGestureIndex);
            end

            idx = allData.GestureNumber == gNum & ...
                  allData.DataType == selectedDataType & ...
                  allData.SampleNumber == sampleNo;

            plotData = allData(idx, :);
            plotData = sortrows(plotData, "Iteration");

            cla(iterationAx);
            if height(plotData) == 0
                title(iterationAx, "Selected Channel Across Iterations");
                xlabel(iterationAx, "Iteration Number");
                ylabel(iterationAx, "Voltage (V)");
                grid(iterationAx, "on");
                channelInfoLabel.Text = "No data for " + selectedText + " yet.";
                return;
            end

            plot(iterationAx, plotData.Iteration, plotData.Voltage, "-o");
            title(iterationAx, "Gesture " + gName + " | Type " + string(selectedDataType) + ...
                " | " + selectedText + " across iterations");
            xlabel(iterationAx, "Iteration Number");
            ylabel(iterationAx, "Voltage (V)");
            iterationAx.XLim = [1 NUM_ITERATIONS];
            iterationAx.XTick = 1:NUM_ITERATIONS;
            grid(iterationAx, "on");

            channelInfoLabel.Text = "Showing " + selectedText + " from " + ...
                string(height(plotData)) + " / " + string(NUM_ITERATIONS) + " iterations.";
        catch ME
            appendLog("Channel plot error: " + ME.message);
        end
    end

    function showCurrentGestureImage()
        if uiGestureIndex < 1
            uiGestureIndex = 1;
        elseif uiGestureIndex > NUM_GESTURES
            uiGestureIndex = NUM_GESTURES;
        end

        % Do NOT clear plots here.
        % When the image changes, keep the previous recording plot visible.
        % The plot is cleared only when the user presses Start for the next recording.

        gName = gestureNames(uiGestureIndex);
        gestureNumberLabel.Text = "Current Gesture Number: " + string(uiGestureIndex);
        gestureNameLabel.Text = "Current Gesture Name: " + gName;
        updateCurrentGestureInfoLabel("Current");
        instructionLabel.Text = "User should make " + gName + ", then click Start.";
        currentRecordLabel.Text = "No recording active.";

        showGestureImage(gName);
    end

    function updateCurrentGestureInfoLabel(statusText)
        try
            if currentGestureNumber > 0 && statusText == "Recording"
                shownNumber = currentGestureNumber;
                shownName = currentGestureName;
            else
                shownNumber = uiGestureIndex;
                shownName = gestureNames(uiGestureIndex);
            end

            currentGestureInfoLabel.Text = statusText + " gesture: " + ...
                string(shownNumber) + " / " + string(NUM_GESTURES) + ...
                " - " + string(shownName);
        catch
        end
    end

    function showGestureImage(gestureName)
        cla(imageAx);
        imageAx.XTick = [];
        imageAx.YTick = [];
        imageAx.Color = [1 1 1];

        if ~isfolder(imageFolder)
            showImageMessage("Image folder not found");
            appendLog("Image folder not found: " + imageFolder);
            return;
        end

        [imagePath, imageFileName] = findGestureImage(gestureName);

        if imagePath == ""
            showImageMessage("Image not found for " + gestureName);
            appendLog("Image not found for gesture: " + gestureName);
            return;
        end

        try
            try
                [img, ~, alpha] = imread(imagePath);
            catch
                img = imread(imagePath);
                alpha = [];
            end

            h = image(imageAx, img);
            if ~isempty(alpha)
                h.AlphaData = alpha;
            end

            axis(imageAx, "image");
            imageAx.XTick = [];
            imageAx.YTick = [];
            title(imageAx, "Current Gesture: " + gestureName);
            appendLog("Displayed image: " + imageFileName);
        catch ME
            showImageMessage("Could not load image");
            appendLog("Image loading error: " + ME.message);
        end
    end

    function clearGestureScreen()
        cla(voltageAx);
        title(voltageAx, "Live Voltage Plot");
        xlabel(voltageAx, "Sample Number / Channel Number");
        ylabel(voltageAx, "Voltage (V)");
        grid(voltageAx, "on");

        clearIterationAxis();
        try
            channelList.Value = "Channel 1";
        catch
        end
        channelInfoLabel.Text = "Select Channel 1 to 40 to compare it across 10 iterations.";
    end

    function clearIterationAxis()
        cla(iterationAx);
        title(iterationAx, "Selected Channel Across Iterations");
        xlabel(iterationAx, "Iteration Number");
        ylabel(iterationAx, "Voltage (V)");
        grid(iterationAx, "on");
    end

    function updateSampleCounterLabel()
        try
            savedHorizontalRows = countCurrentTypeCsvRows();
            expectedHorizontalRows = NUM_GESTURES * SAVED_ITERATIONS;

            sampleCountLabel.Text = "Selected CSV Type " + string(selectedDataType) + ": " + ...
                string(savedHorizontalRows) + " / " + string(expectedHorizontalRows) + ...
                " | File: " + selectedCsvName;
        catch
            sampleCountLabel.Text = "Samples: 0";
        end
    end

    function [ok, voltageValue] = extractVoltageFromLine(line)
        ok = false;
        voltageValue = NaN;

        line = strtrim(string(line));
        if line == ""
            return;
        end

        % Allow bare voltage line: 0.523
        bareValue = str2double(line);
        if ~isnan(bareValue)
            ok = true;
            voltageValue = bareValue;
            return;
        end

        if ~startsWith(line, "DATA")
            return;
        end

        parts = split(line, ",");

        % Final real-life format: DATA,voltage
        if numel(parts) == 2
            v = str2double(parts(2));
            if ~isnan(v)
                ok = true;
                voltageValue = v;
            end
            return;
        end

        % Optional format: DATA,iteration,sample,voltage
        if numel(parts) == 4
            v = str2double(parts(4));
            if ~isnan(v)
                ok = true;
                voltageValue = v;
            end
            return;
        end

        % Older dummy format: DATA,gestureNumber,gestureName,iteration,sampleNumber,voltage,dataType
        if numel(parts) >= 6
            v = str2double(parts(6));
            if ~isnan(v)
                ok = true;
                voltageValue = v;
                return;
            end
        end

        % Fallback: use last numeric field.
        for k = numel(parts):-1:2
            v = str2double(parts(k));
            if ~isnan(v)
                ok = true;
                voltageValue = v;
                return;
            end
        end
    end

    function selected = parseSelectedType()
        selectedText = string(typeList.Value);
        token = regexp(selectedText, '\d+', 'match', 'once');
        selected = str2double(token);
        if isnan(selected) || selected < 1 || selected > NUM_TYPES
            selected = 1;
        end
    end

    function items = makeGestureJumpItems()
        items = strings(NUM_GESTURES, 1);
        for k = 1:NUM_GESTURES
            items(k) = string(k) + " - " + gestureNames(k);
        end
    end

    function [imagePath, imageFileName] = findGestureImage(gestureName)
        imagePath = "";
        imageFileName = "";
        gestureName = string(gestureName);

        baseNames = [gestureName + "_sign"; gestureName; lower(gestureName) + "_sign"; lower(gestureName)];
        extensions = [".png", ".jpg", ".jpeg", ".bmp"];

        candidates = strings(0, 1);
        for b = 1:numel(baseNames)
            for e = 1:numel(extensions)
                candidates(end + 1, 1) = baseNames(b) + extensions(e); %#ok<AGROW>
            end
        end

        for c = 1:numel(candidates)
            directPath = fullfile(imageFolder, candidates(c));
            if isfile(directPath)
                imagePath = directPath;
                imageFileName = candidates(c);
                return;
            end
        end

        for c = 1:numel(candidates)
            found = dir(fullfile(imageFolder, "**", candidates(c)));
            if ~isempty(found)
                imagePath = fullfile(found(1).folder, found(1).name);
                imageFileName = string(found(1).name);
                return;
            end
        end
    end

    function showImageMessage(msg)
        cla(imageAx);
        imageAx.XLim = [0 1];
        imageAx.YLim = [0 1];
        imageAx.XTick = [];
        imageAx.YTick = [];
        text(imageAx, 0.5, 0.5, msg, ...
            "HorizontalAlignment", "center", ...
            "VerticalAlignment", "middle", ...
            "FontSize", 14, ...
            "FontWeight", "bold");
        title(imageAx, "Gesture Image");
    end

    function updateSelectedCsvForType()
        selectedCsvName = typeCsvName(selectedDataType);
        selectedCsvPath = fullfile(saveFolder, selectedCsvName);

        try
            csvFileInfoLabel.Text = "CSV file: " + selectedCsvName;
            csvFolderInfoLabel.Text = "CSV folder: " + saveFolder;
        catch
        end
    end

    function fileName = typeCsvName(typeNumber)
        baseName = erase(string(makeSafeFileName(selectedCsvBaseName)), ".csv");
        fileName = baseName + "_Type" + string(typeNumber) + "_" + scanTypeName(typeNumber) + ".csv";
    end

    function names = readingColumnNames(typeNumber)
        nValues = expectedValuesForType(typeNumber);
        names = strings(1, nValues);
        for colIdx = 1:nValues
            names(colIdx) = "R" + string(colIdx);
        end
    end

    function t = emptyHorizontalCsvTable(typeNumber)
        names = readingColumnNames(typeNumber);
        t = array2table(zeros(0, numel(names)), "VariableNames", cellstr(names));
        t.GestureName = strings(0, 1);
    end

    function t = normalizeHorizontalCsvTable(t, typeNumber)
        expectedNames = [readingColumnNames(typeNumber), "GestureName"];

        if isempty(t)
            t = emptyHorizontalCsvTable(typeNumber);
            return;
        end

        currentNames = string(t.Properties.VariableNames);
        if ~all(ismember(expectedNames, currentNames))
            appendLog("Existing CSV format did not match Type " + string(typeNumber) + ...
                ". A new clean horizontal table will be used.");
            t = emptyHorizontalCsvTable(typeNumber);
            return;
        end

        t = t(:, cellstr(expectedNames));

        readingNames = readingColumnNames(typeNumber);
        for colIdx = 1:numel(readingNames)
            thisName = char(readingNames(colIdx));
            colData = t.(thisName);
            if isnumeric(colData)
                t.(thisName) = double(colData);
            else
                t.(thisName) = str2double(string(colData));
            end
        end
        t.GestureName = string(t.GestureName);
    end

    function t = horizontalTableForLatestRecording(typeNumber)
        nValues = expectedValuesForType(typeNumber);
        readingNames = readingColumnNames(typeNumber);
        iterationList = unique(latestRecordingData.Iteration, "stable");

        matrixData = NaN(numel(iterationList), nValues);
        gestureColumn = strings(numel(iterationList), 1);

        for rowIdx = 1:numel(iterationList)
            iterNo = iterationList(rowIdx);
            rowData = latestRecordingData(latestRecordingData.Iteration == iterNo, :);
            rowData = sortrows(rowData, "SampleNumber");

            values = rowData.Voltage(:)';
            copyCount = min(numel(values), nValues);
            matrixData(rowIdx, 1:copyCount) = values(1:copyCount);
            gestureColumn(rowIdx) = string(rowData.GestureName(1));
        end

        t = array2table(matrixData, "VariableNames", cellstr(readingNames));
        t.GestureName = gestureColumn;
    end

    function n = countCurrentTypeCsvRows()
        n = 0;
        if ~isfile(selectedCsvPath)
            return;
        end

        try
            t = readtable(selectedCsvPath, "TextType", "string");
            t = normalizeHorizontalCsvTable(t, selectedDataType);
            n = height(t);
        catch
            n = 0;
        end
    end

    function t = emptyDataTable()
        t = table( ...
            'Size', [0 7], ...
            'VariableTypes', {'double', 'double', 'string', 'double', 'double', 'double', 'string'}, ...
            'VariableNames', {'DataType', 'GestureNumber', 'GestureName', 'Iteration', 'SampleNumber', 'Voltage', 'Time'} ...
        );
    end

    function t = normalizeDataTable(t)
        requiredNames = {'DataType', 'GestureNumber', 'GestureName', 'Iteration', 'SampleNumber', 'Voltage', 'Time'};

        if isempty(t)
            t = emptyDataTable();
            return;
        end

        for k = 1:numel(requiredNames)
            if ~ismember(requiredNames{k}, t.Properties.VariableNames)
                switch requiredNames{k}
                    case 'DataType'
                        t.DataType = ones(height(t), 1);
                    case 'GestureNumber'
                        t.GestureNumber = zeros(height(t), 1);
                    case 'GestureName'
                        t.GestureName = strings(height(t), 1);
                    case 'Iteration'
                        t.Iteration = zeros(height(t), 1);
                    case 'SampleNumber'
                        t.SampleNumber = zeros(height(t), 1);
                    case 'Voltage'
                        t.Voltage = zeros(height(t), 1);
                    case 'Time'
                        t.Time = strings(height(t), 1);
                end
            end
        end

        t = t(:, requiredNames);

        t.DataType = double(t.DataType);
        t.GestureNumber = double(t.GestureNumber);
        t.GestureName = string(t.GestureName);
        t.Iteration = double(t.Iteration);
        t.SampleNumber = double(t.SampleNumber);
        t.Voltage = double(t.Voltage);
        t.Time = string(t.Time);
    end

    function t = removeGestureTypeRows(t, gestureNumber, dataType)
        if height(t) == 0
            return;
        end
        idxRemove = t.GestureNumber == gestureNumber & t.DataType == dataType;
        t(idxRemove, :) = [];
    end

    function t = sortGestureTable(t)
        if height(t) == 0
            return;
        end
        try
            t = sortrows(t, {'DataType', 'GestureNumber', 'Iteration', 'SampleNumber'});
        catch
        end
    end

    function safeName = makeSafeFileName(name)
        safeName = char(string(name));
        safeName = regexprep(safeName, '[^a-zA-Z0-9_\-.]', '_');
        if strlength(string(safeName)) == 0
            safeName = "gesture_dataset.csv";
        end
    end

    function saveLastPort(portName)
        try
            fid = fopen(lastPortFile, "w");
            if fid ~= -1
                fprintf(fid, "%s", char(portName));
                fclose(fid);
            end
        catch
        end
    end

    function loadLastPortLabel()
        if isfile(lastPortFile)
            try
                saved = strtrim(string(fileread(lastPortFile)));
                if saved ~= ""
                    selectedPort = saved;
                    lastPortLabel.Text = "Last detected port: " + saved;
                else
                    lastPortLabel.Text = "Detected port: none";
                end
            catch
                lastPortLabel.Text = "Detected port: none";
            end
        else
            lastPortLabel.Text = "Detected port: none";
        end
    end

    function sortedPorts = sortPortsHighToLow(portsInput)
        portsInput = string(portsInput);
        if isempty(portsInput)
            sortedPorts = strings(0, 1);
            return;
        end

        nums = zeros(size(portsInput));
        for k = 1:numel(portsInput)
            token = regexp(portsInput(k), '\d+', 'match', 'once');
            if ~isempty(token)
                nums(k) = str2double(token);
            end
        end
        [~, order] = sort(nums, "descend");
        sortedPorts = portsInput(order);
    end

    function lb = createListBox(parentObj, items, startValue, callbackFcn)
        % Older MATLAB versions are strict:
        % Items must be a 1-by-N cell array of CHAR vectors, not cells containing strings.
        items = normalizeSelectorItems(items);
        startValue = char(string(startValue));

        lb = [];
        try
            lb = uilistbox(parentObj);
        catch
            try
                lb = uilistbox("Parent", parentObj);
            catch
                lb = [];
            end
        end

        if isempty(lb)
            % Fallback to dropdown if listbox creation fails on older MATLAB versions.
            try
                lb = uidropdown(parentObj);
            catch
                lb = uidropdown("Parent", parentObj);
            end
        end

        lb.Items = items;

        if any(strcmp(items, startValue))
            lb.Value = startValue;
        else
            lb.Value = items{1};
        end

        if ~isempty(callbackFcn)
            lb.ValueChangedFcn = callbackFcn;
        end
    end

    function itemsOut = normalizeSelectorItems(itemsIn)
        % Convert any input form into 1-by-N cell array of character vectors.
        if iscell(itemsIn)
            itemsOut = cellfun(@(x) char(string(x)), itemsIn, "UniformOutput", false);
        elseif isstring(itemsIn)
            itemsOut = cellstr(itemsIn(:).');
        elseif ischar(itemsIn)
            itemsOut = {itemsIn};
        else
            itemsOut = cellstr(string(itemsIn(:).'));
        end

        itemsOut = reshape(itemsOut, 1, []);

        if isempty(itemsOut)
            itemsOut = {'No items found'};
        end
    end

    function closeCurrentSerial()
        try
            if ~isempty(sp)
                configureCallback(sp, "off");
                flush(sp);
            end
        catch
        end
        sp = [];
    end

    function appendLog(message)
        try
            oldText = string(logBox.Value);
            newText = [oldText; string(message)];
            if numel(newText) > 350
                newText = newText(end-349:end);
            end
            logBox.Value = newText;
            drawnow limitrate;
        catch
        end
    end

    function out = ternary(condition, trueValue, falseValue)
        if condition
            out = trueValue;
        else
            out = falseValue;
        end
    end

    function applyTheme()
        % White / light theme for the complete UI
        figBg      = [1 1 1];
        panelBg    = [1 1 1];
        gridBg     = [1 1 1];
        controlBg  = [1 1 1];
        buttonGrey = [0.86 0.86 0.86];
        buttonBlue = [0.10 0.40 0.80];
        buttonLightBlue = [0.20 0.55 0.90];
        buttonTextDark = [0 0 0];
        buttonTextLight = [1 1 1];
        textColor  = [0 0 0];
        subText    = [0.15 0.15 0.15];

        try
            fig.Color = figBg;
        catch
        end

        % Panels
        panels = [controlPanel, dataPanel, gesturePanel, logPanel];
        for p = panels
            try
                p.BackgroundColor = panelBg;
                p.ForegroundColor = textColor;
            catch
            end
        end

        % Grid/layout backgrounds
        grids = [mainGrid, controlGrid, dataGrid, channelGrid, gestureGrid, logGrid];
        for g = grids
            try
                g.BackgroundColor = gridBg;
            catch
            end
        end

        % Labels and check boxes
        labelControls = [typeLabel, csvNameLabel, jumpLabel, ...
                         connectionInfoLabel, csvFileInfoLabel, csvFolderInfoLabel, ...
                         totalInfoLabel, currentGestureInfoLabel, recordInfoLabel, lastPortLabel, modeInfoLabel, ...
                         channelLabel, channelInfoLabel, gestureNumberLabel, gestureNameLabel, ...
                         sampleCountLabel, connectionLabel, progressLabel, instructionLabel, ...
                         currentRecordLabel];
        for h = labelControls
            try
                h.FontColor = textColor;
            catch
            end
        end

        try
            autoSaveCheck.FontColor = textColor;
        catch
        end

        % Input and list controls
        listControls = [typeList, jumpList, channelList];
        for h = listControls
            try
                h.BackgroundColor = controlBg;
                h.FontColor = textColor;
            catch
            end
        end

        try
            csvNameField.BackgroundColor = controlBg;
            csvNameField.FontColor = textColor;
        catch
        end

        try
            logBox.BackgroundColor = controlBg;
            logBox.FontColor = textColor;
        catch
        end

        % Buttons - grey/blue theme
        % Grey buttons = secondary actions
        greyButtons = [advancedBtn, jumpBtn, setCsvBtn, clearSessionBtn, resetBtn];
        for h = greyButtons
            try
                h.BackgroundColor = buttonGrey;
                h.FontColor = buttonTextDark;
            catch
            end
        end

        % Disconnect button = black
        try
            disconnectBtn.BackgroundColor = [0.05 0.05 0.05];
            disconnectBtn.FontColor = buttonTextLight;
        catch
        end

        % Blue buttons = main action / Arduino communication actions
        blueButtons = [scanBtn, connectBtn, setTypeBtn, startBtn];
        for h = blueButtons
            try
                h.BackgroundColor = buttonBlue;
                h.FontColor = buttonTextLight;
            catch
            end
        end

        % Make Start slightly brighter so it is easy to identify
        try
            startBtn.BackgroundColor = buttonLightBlue;
            startBtn.FontColor = buttonTextLight;
        catch
        end

        % Axes
        axesList = [voltageAx, iterationAx, imageAx];
        for ax = axesList
            try
                ax.Color = [1 1 1];
                ax.XColor = textColor;
                ax.YColor = textColor;
                ax.GridColor = [0.70 0.70 0.70];
                ax.MinorGridColor = [0.85 0.85 0.85];
            catch
            end
        end

        try
            title(voltageAx, "Live Voltage Plot", "Color", textColor);
            xlabel(voltageAx, "Sample Number / Channel Number", "Color", subText);
            ylabel(voltageAx, "Voltage (V)", "Color", subText);

            title(iterationAx, "Selected Channel Across Iterations", "Color", textColor);
            xlabel(iterationAx, "Iteration Number", "Color", subText);
            ylabel(iterationAx, "Voltage (V)", "Color", subText);

            title(imageAx, "Gesture Image", "Color", textColor);
        catch
        end
    end


    function closeApp(~, ~)
        try
            closeCurrentSerial();
        catch
        end
        delete(fig);
    end

end
