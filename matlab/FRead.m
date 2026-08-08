function f = FRead(fd)

    f = NaN;

    try
        flush(fd);              % 🔥 remove stale data
        writeline(fd, '?');     % request new value
        raw = readline(fd);

        raw = strtrim(raw);
        raw = erase(raw, 'N');

        val = -str2double(raw); % compression positive

        if ~isnan(val)
            f = val;
        end

    catch
        % silent fail → handled in main loop
    end
end