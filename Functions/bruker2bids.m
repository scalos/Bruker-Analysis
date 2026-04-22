function bruker2bids(rawDir, outputDir, varargin)
% BRUKER2BIDS Convert Bruker ParaVision raw data to BIDS format
%
% Usage:
%   bruker2bids(rawDir, outputDir)
%   bruker2bids(rawDir, outputDir, 'SubjectLabel', 'sub01')
%   bruker2bids(rawDir, outputDir, 'SessionLabel', 'ses01')
%   bruker2bids(rawDir, outputDir, 'ScanFilter', {'6_13C_C2_Pyr_dyn_spec'})
%
% Inputs:
%   rawDir     - Path to directory containing one or more Bruker session folders
%   outputDir  - Path to BIDS output directory
%
% Optional Name-Value Pairs:
%   SubjectLabel  - Override subject label (default: parsed from subject file)
%   SessionLabel  - Override session label (default: date from session folder name)
%   ScanFilter    - Cell array of ACQ_protocol_name strings to include (default: all)
%
% Example:
%   bruker2bids('/data/RAW', '/data/BIDS', ...
%       'ScanFilter', {'6_13C_C2_Pyr_dyn_spec', 'T2_TurboRARE'})

    p = inputParser;
    addRequired(p,  'rawDir',       @ischar);
    addRequired(p,  'outputDir',    @ischar);
    addParameter(p, 'SubjectLabel', '', @ischar);
    addParameter(p, 'SessionLabel', '', @ischar);
    addParameter(p, 'ScanFilter',   {}, @iscell);
    parse(p, rawDir, outputDir, varargin{:});
    opts = p.Results;

    % Find session folders (directories that contain a 'subject' file)
    sessionDirs = find_session_dirs(rawDir);
    if isempty(sessionDirs)
        error('No valid Bruker session folders found in: %s', rawDir);
    end
    fprintf('Found %d session(s) in %s\n', numel(sessionDirs), rawDir);

    for i = 1:numel(sessionDirs)
        sesDir = sessionDirs{i};
        fprintf('\n--- Processing session: %s ---\n', sesDir);
        try
            process_session(sesDir, outputDir, opts);
        catch ME
            warning('Failed to process session %s:\n  %s', sesDir, ME.message);
        end
    end

    write_dataset_description(outputDir);
    fprintf('\nDone. BIDS data written to: %s\n', outputDir);
end


% =========================================================================
%  Session-level processing
% =========================================================================

function sessionDirs = find_session_dirs(rawDir)
% Return subdirectories of rawDir that contain a Bruker 'subject' file
    sessionDirs = {};
    entries = dir(rawDir);
    for i = 1:numel(entries)
        if ~entries(i).isdir || entries(i).name(1) == '.', continue; end
        candidate = fullfile(rawDir, entries(i).name);
        if exist(fullfile(candidate, 'subject'), 'file')
            sessionDirs{end+1} = candidate; %#ok<AGROW>
        end
    end
end


function process_session(sesDir, outputDir, opts)
    subjectFile = fullfile(sesDir, 'subject');
    subjectMeta = parse_bruker_params(subjectFile);

    subLabel = pick_label(opts.SubjectLabel, get_subject_label(subjectMeta));
    sesLabel = pick_label(opts.SessionLabel, get_session_label(sesDir));

    fprintf('  Subject: sub-%s  |  Session: ses-%s\n', subLabel, sesLabel);

    scanDirs = find_scan_dirs(sesDir);
    if isempty(scanDirs)
        warning('No scan directories found in %s', sesDir);
        return;
    end

    runCounters = struct();   % track per-modality run indices

    for i = 1:numel(scanDirs)
        try
            runCounters = process_scan(scanDirs{i}, outputDir, ...
                                       subLabel, sesLabel, opts, runCounters);
        catch ME
            warning('  Skipping scan %s:\n    %s', scanDirs{i}, ME.message);
        end
    end
end


% =========================================================================
%  Scan-level processing
% =========================================================================

function runCounters = process_scan(scanDir, outputDir, subLabel, sesLabel, opts, runCounters)
    acqpFile   = fullfile(scanDir, 'acqp');
    methodFile = fullfile(scanDir, 'method');
    if ~exist(acqpFile,'file') || ~exist(methodFile,'file'), return; end

    acqp   = parse_bruker_params(acqpFile);
    method = parse_bruker_params(methodFile);

    % Apply optional scan filter (matches on ACQ_protocol_name)
    if ~isempty(opts.ScanFilter)
        protName = get_field(acqp, 'ACQ_protocol_name', '');
        if ~any(strcmpi(protName, opts.ScanFilter))
            return;
        end
    end

    % Classify the scan
    [bidsType, bidsModality, suffix] = classify_scan(acqp, method);
    if isempty(bidsType)
        fprintf('    [SKIP] Unclassifiable scan: %s\n', scanDir);
        return;
    end

    % Assign run index
    runKey = matlab.lang.makeValidName([bidsModality '_' suffix]);
    if ~isfield(runCounters, runKey), runCounters.(runKey) = 0; end
    runCounters.(runKey) = runCounters.(runKey) + 1;
    runIdx = runCounters.(runKey);

    % Build BIDS filename
    acqLabel = sanitize_label(get_field(acqp, 'ACQ_protocol_name', 'unknown'));
    entities = struct('sub', subLabel, 'ses', sesLabel, ...
                      'acq', acqLabel, 'run', sprintf('%02d', runIdx));
    fname = build_bids_filename(entities, suffix);

    % Create output folder
    outDir = fullfile(outputDir, ['sub-' subLabel], ['ses-' sesLabel], bidsModality);
    if ~exist(outDir,'dir'), mkdir(outDir); end

    % Read data
    [data, dimInfo] = read_bruker_data(scanDir, acqp, method);

    % Write data file
    if strcmp(bidsType, 'spectroscopy')
        write_mrs_data(data, dimInfo, outDir, fname, acqp, method);
    else
        write_nifti(data, dimInfo, outDir, fname, acqp, method);
    end

    % Write JSON sidecar
    write_json_sidecar(outDir, fname, acqp, method, bidsType);

    fprintf('    [OK] %s/%s\n', bidsModality, fname);
end


% =========================================================================
%  Classification
% =========================================================================

function [bidsType, bidsModality, suffix] = classify_scan(acqp, method)
% Classify scan into BIDS type / modality folder / filename suffix
%
% Logic:
%   - Non-proton nucleus OR spectroscopic encoding  -> mrs / svs or mrsi
%   - 1H + multiple repetitions + spatial dims      -> func / bold
%   - 1H + single volume                            -> anat / T2w

    bidsType = ''; bidsModality = ''; suffix = '';

    nucleus  = strtrim(get_field(acqp, 'NUCLEUS', get_field(method, 'PVM_Nucleus1', '1H')));
    dimDesc  = get_field(acqp, 'ACQ_dim_desc', '');
    encSpec  = get_field(method, 'PVM_EncSpectroscopy', 'No');
    specDim  = get_field(method, 'PVM_SpecDim', 0);
    nRep     = get_field(acqp,   'NR', 1);
    acqDim   = get_field(acqp,   'ACQ_dim', 1);

    isSpec      = strcmpi(dimDesc, 'Spectroscopic') || strcmpi(encSpec, 'Yes') || ...
                  (isnumeric(specDim) && specDim >= 1);
    isNonProton = ~any(strcmpi(nucleus, {'1H','H'}));

    if isSpec || isNonProton
        bidsType     = 'spectroscopy';
        bidsModality = 'mrs';
        if isnumeric(specDim) && specDim > 1
            suffix = 'mrsi';   % spatially resolved spectroscopy
        else
            suffix = 'svs';    % single-voxel spectroscopy
        end

    elseif isnumeric(nRep) && nRep > 1 && isnumeric(acqDim) && acqDim >= 2
        bidsType     = 'func';
        bidsModality = 'func';
        suffix       = 'bold';

    else
        bidsType     = 'anat';
        bidsModality = 'anat';
        suffix       = 'T2w';  % default anatomical; refine if needed
    end
end


% =========================================================================
%  Data reading
% =========================================================================

function [data, dimInfo] = read_bruker_data(scanDir, acqp, method)
% Read reconstructed (2dseq) or raw (fid) data

    dimInfo  = struct();
    data     = [];
    pdataDir = fullfile(scanDir, 'pdata', '1');
    seqFile  = fullfile(pdataDir, '2dseq');
    visuFile = fullfile(pdataDir, 'visu_pars');

    if exist(seqFile, 'file')
        visu = struct();
        if exist(visuFile, 'file')
            visu = parse_bruker_params(visuFile);
        end
        [data, dimInfo] = read_2dseq(seqFile, acqp, method, visu);
    else
        fidFile = fullfile(scanDir, 'fid');
        if exist(fidFile, 'file')
            [data, dimInfo] = read_fid(fidFile, acqp, method);
        else
            error('No 2dseq or fid file found in %s', scanDir);
        end
    end
end


function [data, dimInfo] = read_2dseq(seqFile, acqp, method, visu)
    dimInfo = struct('visu', visu);

    wordSize = get_field(acqp, 'ACQ_word_size', '_32_BIT');
    if contains(wordSize, '32'), dtype = 'int32'; else, dtype = 'int16'; end

    byteOrder = get_field(acqp, 'BYTORDA', 'little');
    mf = 'l'; if strcmpi(byteOrder,'big'), mf = 'b'; end

    fid  = fopen(seqFile, 'r', mf);
    data = fread(fid, inf, dtype);
    fclose(fid);

    % Determine reshape dimensions from visu_pars
    if isfield(visu, 'VisuCoreSize')
        dims = visu.VisuCoreSize(:)';
    else
        dims = get_field(acqp, 'ACQ_size', numel(data));
    end
    dimInfo.dims = dims;

    % Extract voxel sizes
    if isfield(visu,'VisuCoreExtent') && isfield(visu,'VisuCoreSize')
        ext = visu.VisuCoreExtent(:)';
        sz  = visu.VisuCoreSize(:)';
        dimInfo.pixdim = ext ./ sz;
    else
        dimInfo.pixdim = ones(1,3);
    end

    try, data = reshape(data, dims); catch, end
end


function [data, dimInfo] = read_fid(fidFile, acqp, method)
    byteOrder = get_field(acqp, 'BYTORDA', 'little');
    mf = 'l'; if strcmpi(byteOrder,'big'), mf = 'b'; end

    fid = fopen(fidFile, 'r', mf);
    raw = fread(fid, inf, 'int32');
    fclose(fid);

    data = complex(raw(1:2:end), raw(2:2:end));

    nPoints = get_field(acqp,   'ACQ_size', numel(data));  if iscell(nPoints), nPoints = nPoints{1}; end
    nRep    = get_field(acqp,   'NR',       1);
    nAvg    = get_field(acqp,   'NA',       1);

    dimInfo = struct( ...
        'nPoints',     nPoints, ...
        'nRep',        nRep, ...
        'nAvg',        nAvg, ...
        'dwellTime_us', get_field(method, 'PVM_SpecDwellTime', 1), ...
        'swh',          get_field(method, 'PVM_SpecSWH', get_field(acqp,'SW_h',0)), ...
        'pixdim',       [1 1 1]);

    try, data = reshape(data, nPoints, nAvg, nRep); catch, end
end


% =========================================================================
%  Data writing
% =========================================================================

function write_nifti(data, dimInfo, outDir, fname, acqp, method)
    pixdim = dimInfo.pixdim;
    if numel(pixdim) < 3, pixdim(end+1:3) = 1; end
    write_nii_simple(fullfile(outDir, [fname '.nii']), single(data), pixdim);
end


function write_mrs_data(data, dimInfo, outDir, fname, acqp, method)
% Write MRS/spectroscopy data as NIfTI (BEP-031 compliant layout)
% Complex FID data is stored as [Re Im] along the first dimension

    if ~isreal(data)
        nPts  = size(data,1);
        nAvg  = size(data,2);
        nRep  = size(data,3);
        % Interleave real/imag for NIfTI storage
        out   = zeros(2, nPts, nAvg, nRep, 'single');
        out(1,:,:,:) = real(data);
        out(2,:,:,:) = imag(data);
    else
        out = single(data);
    end
    write_nii_simple(fullfile(outDir, [fname '.nii']), out, [1 1 1]);
end


function write_nii_simple(outFile, data, pixdim)
% Minimal NIfTI-1 writer — no toolbox required
    data  = single(data);
    dims  = size(data);
    ndim  = numel(dims);

    % Zero-pad pixdim to 3 elements
    if numel(pixdim) < 3, pixdim(end+1:3) = 1; end

    hdr = zeros(1, 348, 'uint8');
    % sizeof_hdr
    hdr(1:4)   = typecast(int32(348), 'uint8');
    % dim[0..7]: number of dims, then sizes
    dimArr     = int16([ndim, dims(1:min(ndim,7)), ones(1, 7-min(ndim,7))]);
    hdr(41:56) = typecast(dimArr, 'uint8');
    % datatype=16 (float32), bitpix=32
    hdr(71:72) = typecast(int16(16), 'uint8');
    hdr(73:74) = typecast(int16(32), 'uint8');
    % pixdim[0..7]
    pdArr      = single([1, pixdim(1), pixdim(2), pixdim(3), 1, 1, 1, 1]);
    hdr(77:108)= typecast(pdArr, 'uint8');
    % vox_offset=352
    hdr(109:112)= typecast(single(352), 'uint8');
    % scl_slope=1
    hdr(113:116)= typecast(single(1), 'uint8');
    % xyzt_units=2 (mm)
    hdr(123)   = uint8(2);
    % magic 'n+1\0'
    hdr(345:348)= uint8([110, 43, 49, 0]);

    fid = fopen(outFile, 'w');
    fwrite(fid, hdr,          'uint8');
    fwrite(fid, zeros(1,4,'uint8'), 'uint8');  % 4-byte extension block
    fwrite(fid, data(:),      'float32');
    fclose(fid);
end


function write_json_sidecar(outDir, fname, acqp, method, bidsType)
% Write BIDS-compliant JSON sidecar

    j = struct();

    % --- Fields common to all modalities ---
    j.Manufacturer              = 'Bruker';
    j.ManufacturersModelName    = get_field(acqp, 'ACQ_station',      'Unknown');
    j.SoftwareVersions          = get_field(acqp, 'ACQ_sw_version',   'Unknown');
    j.InstitutionName           = get_field(acqp, 'ACQ_institution',  'Unknown');
    j.PulseSequenceType         = get_field(acqp, 'ACQ_method',       get_field(method,'Method','Unknown'));
    j.SequenceName              = get_field(acqp, 'PULPROG',          'Unknown');
    j.FlipAngle                 = get_field(acqp, 'ACQ_flip_angle',   []);
    j.NumberOfAverages          = get_field(acqp, 'NA',               get_field(method,'PVM_NAverages',[]));

    % RepetitionTime in seconds (Bruker stores in ms)
    tr_ms = get_field(acqp, 'ACQ_repetition_time', get_field(method,'PVM_RepetitionTime',[]));
    if ~isempty(tr_ms), j.RepetitionTime = tr_ms / 1000; end

    % EchoTime in seconds
    te_ms = get_field(acqp, 'ACQ_echo_time', get_field(method,'EchoTime',[]));
    if ~isempty(te_ms), j.EchoTime = te_ms / 1000; end

    % --- Modality-specific fields ---
    switch bidsType
        case 'spectroscopy'
            j.ResonantNucleus         = get_field(acqp,   'NUCLEUS',          get_field(method,'PVM_Nucleus1','1H'));
            j.SpectrometerFrequency   = get_field(acqp,   'BF1',              get_field(method,'PVM_FrqWork',[]));
            j.SpectralWidth           = get_field(method,  'PVM_SpecSW',       []);   % ppm
            j.SpectralWidthHz         = get_field(method,  'PVM_SpecSWH',      get_field(acqp,'SW_h',[]));
            j.NumberOfSpectralPoints  = get_field(method,  'PVM_SpecMatrix',   get_field(acqp,'ACQ_size',[]));
            j.NumberOfTransients      = get_field(acqp,    'NR',               get_field(method,'PVM_NRepetitions',[]));
            j.WaterSuppression        = get_field(method,  'PVM_WsOnOff',      'Unknown');
            j.AcquisitionVoxelSize    = get_field(method,  'SliceThick',       []);

        case 'func'
            j.TaskName = 'rest';

        case 'anat'
            % no extra required fields beyond common ones
    end

    % Remove empty fields
    fields = fieldnames(j);
    for i = 1:numel(fields)
        if isempty(j.(fields{i})), j = rmfield(j, fields{i}); end
    end

    fid = fopen(fullfile(outDir, [fname '.json']), 'w');
    fprintf(fid, '%s', jsonencode(j, 'PrettyPrint', true));
    fclose(fid);
end


function write_dataset_description(outputDir)
    outFile = fullfile(outputDir, 'dataset_description.json');
    if exist(outFile, 'file'), return; end
    if ~exist(outputDir,'dir'), mkdir(outputDir); end
    desc = struct('Name', 'Bruker MRI Dataset', ...
                  'BIDSVersion', '1.8.0', ...
                  'GeneratedBy', struct('Name','bruker2bids','Version','1.0'));
    fid = fopen(outFile, 'w');
    fprintf(fid, '%s', jsonencode(desc, 'PrettyPrint', true));
    fclose(fid);
end


% =========================================================================
%  Bruker parameter file parser
% =========================================================================

function params = parse_bruker_params(filepath)
% Parse a Bruker JCAMP-DX parameter file (acqp, method, subject, visu_pars)
% into a MATLAB struct.
%
% Handles:
%   - Scalar integers and floats
%   - String values in angle brackets <...>
%   - 1D and 2D numeric arrays in parentheses (n) or (m,n)
%   - Cell/string arrays
%   - Skips comment lines ($$ ...) and directives (##TITLE etc.)

    params = struct();
    if ~exist(filepath, 'file')
        warning('Parameter file not found: %s', filepath);
        return;
    end

    fid  = fopen(filepath, 'r');
    text = fread(fid, inf, '*char')';
    fclose(fid);

    % Normalise line endings
    text = strrep(text, char(13), '');
    lines = strsplit(text, char(10));

    i = 1;
    while i <= numel(lines)
        line = strtrim(lines{i});

        % Skip comments and JCAMP directives (except ##$)
        if isempty(line) || strncmp(line,'$$',2) || ...
           (strncmp(line,'##',2) && ~strncmp(line,'##$',3))
            i = i + 1;
            continue;
        end

        if strncmp(line, '##$', 3)
            % Parse  ##$KEY=VALUE
            eqIdx = strfind(line, '=');
            if isempty(eqIdx)
                i = i + 1; continue;
            end
            key   = strtrim(line(4:eqIdx(1)-1));
            value = strtrim(line(eqIdx(1)+1:end));

            % Collect continuation lines (array data / multi-line strings)
            while i+1 <= numel(lines)
                nextLine = strtrim(lines{i+1});
                % Stop at next ## entry or empty
                if strncmp(nextLine,'##',2) || isempty(nextLine)
                    break;
                end
                value = [value ' ' nextLine]; %#ok<AGROW>
                i = i + 1;
            end

            params.(matlab.lang.makeValidName(key)) = parse_value(value);
        end
        i = i + 1;
    end
end


function val = parse_value(str)
% Convert a Bruker parameter value string to an appropriate MATLAB type

    str = strtrim(str);

    % String in angle brackets: <...>
    if str(1) == '<'
        closing = find(str == '>', 1, 'last');
        if ~isempty(closing)
            val = strtrim(str(2:closing-1));
        else
            val = str;
        end
        return;
    end

    % Array size specifier followed by data: (n) data...  or (m, n) data...
    if str(1) == '('
        closing = find(str == ')', 1);
        if ~isempty(closing)
            sizeStr = str(2:closing-1);
            datStr  = strtrim(str(closing+1:end));
            szTokens = str2num(sizeStr); %#ok<ST2NM>

            if isempty(datStr)
                val = szTokens;
                return;
            end

            % Try numeric array first
            nums = str2num(datStr); %#ok<ST2NM>
            if ~isempty(nums)
                try
                    val = reshape(nums, fliplr(szTokens))';
                catch
                    val = nums;
                end
                return;
            end

            % String / enum array — split on whitespace
            val = strsplit(datStr);
            % Strip angle brackets from each element
            val = cellfun(@(s) regexprep(s,'<|>',''), val, 'UniformOutput', false);
            return;
        end
    end

    % Plain number or array of numbers
    nums = str2num(str); %#ok<ST2NM>
    if ~isempty(nums)
        val = nums;
        return;
    end

    % Enum string (no brackets)
    val = str;
end


% =========================================================================
%  Utility helpers
% =========================================================================

function val = get_field(s, fieldName, default)
    if nargin < 3, default = []; end
    if isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = default;
    end
end

function label = pick_label(override, fallback)
    if ~isempty(override)
        label = sanitize_label(override);
    else
        label = fallback;
    end
end

function label = get_subject_label(subjectMeta)
    raw = get_field(subjectMeta, 'SUBJECT_id', ...
          get_field(subjectMeta, 'SUBJECT_study_name', 'unknown'));
    label = sanitize_label(raw);
end

function label = get_session_label(sesDir)
    [~, folderName] = fileparts(sesDir);
    tok = regexp(folderName, '^(\d{8})', 'tokens', 'once');
    if ~isempty(tok)
        label = tok{1};
    else
        label = sanitize_label(folderName(1:min(8,end)));
    end
end

function label = sanitize_label(str)
    if iscell(str), str = str{1}; end
    label = regexprep(str, '[^a-zA-Z0-9]', '');
    if isempty(label), label = 'unknown'; end
end

function fname = build_bids_filename(entities, suffix)
% Assemble BIDS filename respecting canonical entity order
    orderedKeys = {'sub','ses','task','acq','ce','rec','dir','run','echo','part'};
    parts = {};
    for i = 1:numel(orderedKeys)
        k = orderedKeys{i};
        if isfield(entities, k) && ~isempty(entities.(k))
            parts{end+1} = [k '-' entities.(k)]; %#ok<AGROW>
        end
    end
    fname = [strjoin(parts,'_') '_' suffix];
end

function scanDirs = find_scan_dirs(sesDir)
% Return numbered scan subdirectories (those containing an 'acqp' file)
    scanDirs = {};
    nums     = [];
    entries  = dir(sesDir);
    for i = 1:numel(entries)
        if ~entries(i).isdir || entries(i).name(1) == '.', continue; end
        candidate = fullfile(sesDir, entries(i).name);
        if exist(fullfile(candidate,'acqp'),'file')
            n = str2double(entries(i).name);
            scanDirs{end+1} = candidate; %#ok<AGROW>
            nums(end+1)     = n; %#ok<AGROW>
        end
    end
    % Sort numerically
    [~, idx] = sort(nums);
    scanDirs = scanDirs(idx);
end
