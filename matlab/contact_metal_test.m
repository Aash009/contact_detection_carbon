clear; close all; clc;

global strokeCount contactDetected tlog;
strokeCount     = 0;
contactDetected = false;

%% ================= MOTOR SETUP =================
f = figure('Name','Contact Metal Test','Position',[200 100 800 600]);
h = actxcontrol('MGMOTOR.MGMotorCtrl.1',[20 250 600 300], f);
h.StartCtrl;
set(h, 'HWSerialNum', 45181764);
h.Identify;
pause(6);

%% ================= FORCE GAUGE =================
forcePort = serialport('COM14', 9600);
configureTerminator(forcePort, "CR");
forcePort.Timeout = 1;
flush(forcePort);

%% ================= STM32 CONTACT / STROKE DETECTOR =================
stmPort = [];
try
    stmPort = serialport('COM30', 115200);
    configureTerminator(stmPort, "CR/LF");
    flush(stmPort);
    configureCallback(stmPort, "terminator", @stmCallback);
    pause(0.5);                    % wait for STM32 to finish startup
    write(stmPort, 'R', "uint8");  % reset STM32 stroke counter
    pause(0.2);                    % allow STM32 to process reset
    fprintf('Connected to STM32 on COM30.\n');
catch ME
    fclose all;
    error('STM32 unavailable: %s\nContact-triggered test cannot run without it.', ME.message);
end

%% ================= PARAMETERS =================
% Hardcoded stroke endpoints (mm).
START_POS = 121.79;  % stage returns here after every contact

% END_POS is a SAFETY BACKSTOP only — the forward move stops on
% contact detection, not on reaching this position. Set it comfortably
% past the real contact point but within the stage's travel limit.
SAFETY_END_POS = 300.0000;

OSC_VEL   = 1.5;      OSC_ACC   = 1;
SAMPLE_DT = 0.05;   % force/position sample interval (s)
MOVE_TOL  = 0.005;  % position tolerance for "arrived" (mm)
VEL_SETTLE = 0.3;   % settle time after SetVelParams (s)

cycles = input('Enter number of cycles: ');

%% ================= CSV FILE =================
csvFile = 'contact_metal.csv';
fid = fopen(csvFile, 'w');
fprintf(fid, 'Cycle,Direction,Position_mm,Force_N,StrokeCount,Time_s\n');
tlog = tic;

%% ================= MOVE TO START POSITION =================
fprintf('\nMoving to START (%.4f mm)...\n', START_POS);
h.SetVelParams(0, 0, OSC_ACC, OSC_VEL);
pause(VEL_SETTLE);

startFinalPos = moveToPosAndWait(h, START_POS, MOVE_TOL, SAMPLE_DT, [], [], 0, '');
if abs(startFinalPos - START_POS) > MOVE_TOL
    fclose(fid);
    error('Failed to reach START_POS (at %.4f mm). Aborting.', startFinalPos);
end
fprintf('At START: %.4f mm\n', startFinalPos);

%% ================= CYCLING =================
for cycle = 1:cycles

    fprintf('\n===== Cycle %d / %d  (strokes so far: %d) =====\n', ...
        cycle, cycles, strokeCount);

    % --- FORWARD: drive until STM32 fires, safety limit is the backstop ---
    contactDetected = false;
    fwdFinal = moveForwardUntilContact(h, SAFETY_END_POS, MOVE_TOL, SAMPLE_DT, forcePort, fid, cycle);

    if ~contactDetected
        warning('Cycle %d FWD: reached SAFETY_END_POS (%.4f mm) with NO contact signal. Check sensor/wiring.', ...
            cycle, SAFETY_END_POS);
    else
        fprintf('Cycle %d contact at %.4f mm.\n', cycle, fwdFinal);
    end

    % --- BACKWARD: return to known START_POS (absolute move, no relative arithmetic) ---
    bwdFinal = moveToPosAndWait(h, START_POS, MOVE_TOL, SAMPLE_DT, forcePort, fid, cycle, 'BWD');
    if abs(bwdFinal - START_POS) > MOVE_TOL
        warning('Cycle %d BWD: reached %.4f mm, target %.4f mm.', cycle, bwdFinal, START_POS);
    end

end

%% ================= CLEANUP =================
fclose(fid);
clear forcePort;
if ~isempty(stmPort); clear stmPort; end

%% ================= REPORT =================
fprintf('\n=================================\n');
fprintf('TEST COMPLETE  —  %s\n', csvFile);
fprintf('Cycles commanded : %d\n', cycles);
fprintf('STM32 strokes    : %d\n', strokeCount);
if strokeCount == cycles
    fprintf('MATCH\n');
else
    fprintf('MISMATCH (%d expected, %d seen) — check debounce/wiring.\n', cycles, strokeCount);
end
fprintf('=================================\n');


%% ================= LOCAL FUNCTIONS =================

% Drives to a fixed absolute position and waits until within tolerance.
% Used for: initial move to START_POS and every BWD return.
function finalPos = moveToPosAndWait(h, targetPos, tol, dt, forcePort, fid, cycle, direction)
    global strokeCount tlog

    doLog = ~isempty(forcePort);

    h.SetAbsMovePos(0, targetPos);
    h.MoveAbsolute(0, 0);

    while true
        posVal = h.GetPosition_Position(0);

        if doLog
            forceVal = FRead(forcePort);
            fprintf(fid, '%d,%s,%.5f,%.5f,%d,%.3f\n', ...
                cycle, direction, posVal, forceVal, strokeCount, toc(tlog));
            fprintf('%s | Pos=%.4f mm | Force=%.4f N | Strokes=%d\n', ...
                direction, posVal, forceVal, strokeCount);
        end

        if abs(posVal - targetPos) < tol
            break;
        end

        pause(dt);
    end

    finalPos = h.GetPosition_Position(0);
end

% Drives toward safetyLimitPos but stops the INSTANT STM32 fires.
% safetyLimitPos is never expected to be reached in normal operation.
function finalPos = moveForwardUntilContact(h, safetyLimitPos, tol, dt, forcePort, fid, cycle)
    global contactDetected strokeCount tlog

    h.SetAbsMovePos(0, safetyLimitPos);
    h.MoveAbsolute(0, 0);

    while true
        posVal   = h.GetPosition_Position(0);
        forceVal = FRead(forcePort);

        fprintf(fid, '%d,%s,%.5f,%.5f,%d,%.3f\n', ...
            cycle, 'FWD', posVal, forceVal, strokeCount, toc(tlog));
        fprintf('FWD | Pos=%.4f mm | Force=%.4f N | Strokes=%d\n', ...
            posVal, forceVal, strokeCount);

        % contactDetected is set by stmCallback asynchronously
        if contactDetected
            break;
        end

        if abs(posVal - safetyLimitPos) < tol
            break;   % backstop reached with no contact — loop will exit
        end

        pause(dt);
    end

    % Explicit stop so the controller doesn't keep driving while MATLAB
    % runs the BWD setup; this is the key call that was missing before.
    safeStop(h);

    finalPos = h.GetPosition_Position(0);
end

% -------------------------------------------------------
function safeStop(h)
    try
        h.StopImmediate(0);
    catch
        try
            h.MoveStop(0, 0);
        catch
            warning('Could not send stop command to controller.');
        end
    end
    pause(0.3);
end

% -------------------------------------------------------
function f = FRead(fd)
    f = NaN;
    try
        flush(fd);
        writeline(fd, '?');
        raw = strtrim(readline(fd));
        raw = erase(raw, 'N');
        val = -str2double(raw);   % compression -> positive
        if ~isnan(val)
            f = val;
        end
    catch
    end
end

% -------------------------------------------------------
% Parses "Stroke count: 42\r\n" from STM32 firmware exactly.
function stmCallback(src, ~)
    global strokeCount contactDetected
    line = strtrim(readline(src));
    % Match STM32 format: "Stroke count: <n>"
    tok = regexp(line, '^Stroke count:\s*(\d+)$', 'tokens', 'once');
    if ~isempty(tok)
        n = str2double(tok{1});
        if ~isnan(n) && n > strokeCount
            strokeCount     = n;
            contactDetected = true;
            fprintf('[STM32] contact! stroke count = %d\n', strokeCount);
        end
    end
end
