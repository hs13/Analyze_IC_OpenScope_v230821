clear all; close all; %clc

%addpath(genpath('/Users/hyeyoung/Documents/CODE/matnwb'))
addpath(genpath('d:\Users\USER\Documents\MATLAB\matnwb'))
addpath(genpath('C:\Users\USER\GitHub\SpectralEvents')) % for TFR

datadir = 'S:\OpenScopeData\00248_v240130\';
nwbdir = dir(datadir);
nwbsessions = {nwbdir.name};
nwbsessions = nwbsessions( contains(nwbsessions, 'sub-') | contains(nwbsessions, 'sub_') );

% probes = {'A', 'B', 'C', 'D', 'E'};
% visareas = {'AM', 'PM', 'V1', 'LM', 'AL', 'RL'};

probes = {'D', 'E'};

for ises = 1:numel(nwbsessions)
    clearvars -except ises datadir nwbsessions probes
    sesclk = tic;
    pathpp = [datadir 'postprocessed' filesep nwbsessions{ises} filesep];
    nwbfiles = cat(1, dir([datadir nwbsessions{ises} filesep '*.nwb']), dir([datadir nwbsessions{ises} filesep '*' filesep '*.nwb']));

    nwblfpfiles = nwbfiles(contains({nwbfiles.name}, 'probe'));
    if isempty(nwblfpfiles)
        fprintf('%d/%d %s does not have LFP recordings\n', ises, numel(nwbsessions), nwbsessions{ises})
        continue
    end

    % take filename  with shortest length or filename that does not contain probe
    [~, fileind] = min(cellfun(@length, {nwbfiles.name}));
    nwbspikefile = fullfile([nwbfiles(fileind).folder filesep nwbfiles(fileind).name]);
    % nwbspikefile = string(nwbspikefile);
    % disp(nwbspikefile)
    nwb = nwbRead(nwbspikefile); %, 'ignorecache');

    %% extract spike times
    unit_ids = nwb.units.id.data.load(); % array of unit ids represented within this session
    unit_peakch = nwb.units.vectordata.get('peak_channel_id').data.load();
    unit_times_data = nwb.units.spike_times.data.load();
    unit_times_idx = nwb.units.spike_times_index.data.load();
    % unit_waveform = nwb.units.waveform_mean.data.load();
    unit_wfdur = nwb.units.vectordata.get('waveform_duration').data.load();

    Nunits = length(unit_ids);

    % all(ismember(unit_peakch, electrode_id))

    spiketimes = cell(Nunits, 1);
    last_idx = 0;
    for ii = 1:Nunits
        unit_id = unit_ids(ii);

        %     assert(unit_trials_idx(i) == unit_times_idx(i), 'Expected unit boundaries to match between trials & spike_times jagged arrays')
        start_idx = last_idx + 1;
        end_idx = unit_times_idx(ii);

        spiketimes{ii} = unit_times_data(start_idx:end_idx);

        last_idx = end_idx;
    end

    load( [pathpp 'postprocessed.mat'], 'Tres', 'vis', 'neuallloc' )
    neuindV1 = find( contains(neuallloc, 'VISp') & ~contains(neuallloc, 'VISpm') );
    Nneurons = numel(neuindV1);

    load([pathpp 'info_electrodes.mat'])
    load([pathpp 'info_units.mat'])
    V1elec = electrode_id( contains(electrode_location, 'VISp') & ~contains(electrode_location, 'VISpm') );
    if ~all(ismember(unit_peakch(neuindV1), V1elec))
        error('check neuallloc')
    end

    load( [pathpp 'LFP1000Hz_probeC.mat'], 'lfptimeresamp' )
    ststart = floor((vis.ICwcfg1_presentations.start_time(1))/Tres)+1;
    stend = floor((vis.ICwcfg1_presentations.stop_time(end))/Tres)+1;
    stlen = round((lfptimeresamp(end))/Tres);
    
    spiketrain = false(stlen, Nneurons);
    for ii = 1:Nneurons
        ci = neuindV1(ii);
        spiketrain(floor(spiketimes{ci}/Tres)+1, ii) = true;
    end
    spiketrain = spiketrain(ststart:stend,:);

    lfpts1 = floor((lfptimeresamp(1))/Tres)+1;
    lfpstart = ststart-lfpts1;
    lfpend = stend-lfpts1;
    if stend-ststart ~= lfpend-lfpstart
        error('mismatch between spike train length and lfp length')
    end


    %% spike triggered CSD and TFR
    for iprobe = 1:numel(probes)
        fprintf('%d/%d %s Probe%s\n', ises, numel(nwbsessions), nwbsessions{ises}, probes{iprobe})
        if exist(sprintf('%sV1spiketriggered_LFP_CSD_TFR_probe%s.mat', pathpp, probes{iprobe}), 'file')
            fprintf('V1spiketriggered_LFP_CSD_TFR_probe%s.mat already exits\n', probes{iprobe})
            continue
        end

        probeclk = tic;
        load( sprintf('%sLFP1000Hz_probe%s.mat', pathpp, probes{iprobe}) )

        % 'lfpelecid', 'lfpelecvec', 'lfptimeresamp', 'lfpresamp'
        lfpblock = lfpresamp(:,lfpstart:lfpend);

        %% CSD: negative values mean sink (influx, depol), positive values mean source (outflux)
        % lfpelecspacing = 0.04; % 40micrometers, i.e., 0.04mm
        % csdelectinds = 2:Nelec-1;
        % csdresamp = -( lfpresamp(csdelectinds+1,:)-2*lfpresamp(csdelectinds,:)+lfpresamp(csdelectinds-1,:) )/(lfpelecspacing.^2);

        % smooth with a gaussian kernel first
        kerwinhalf = 5; kersigma = 2;
        kergauss = normpdf( (-kerwinhalf:kerwinhalf), 0,kersigma);
        kergauss = (kergauss/sum(kergauss));
        lfpconv = convn(lfpblock, kergauss, 'same');

        Nelec = numel(lfpelecid);
        lfpelecspacing = 0.04; % 40micrometers, i.e., 0.04mm
        csdelectinds = 2:Nelec-1;
        csdblock = -( lfpconv(csdelectinds+1,:)-2*lfpconv(csdelectinds,:)+lfpconv(csdelectinds-1,:) )/(lfpelecspacing.^2);

        %% TFR : for now, just choose one electrode in layer 2/3
        load(sprintf('%sLFP_TFR_L23_probe%s.mat', pathpp, probes{iprobe}), 'elecL23')
        %elecL23 = round(median( find(contains(lfpelecvec.location, '2/3')) ));
        electrodesL23 = find(contains(lfpelecvec.location(csdelectinds), '2/3'));

        % 30 seconds and 7 GB for each electrode
        S = lfpblock(elecL23,:)';
        % get rid of NaN values in S
        [TFR_L23_block,tVec,fVec] = spectralevents_ts2tfr(S,1:100,1/Tres,5);

        %% spike triggered CSD and TFR
        Twin = 250;
        trange = -Twin:Twin;
        spiketraintrimmed = spiketrain;
        spiketraintrimmed(1:Twin,:)=false;
        spiketraintrimmed(end-Twin+1:end,:)=false;
        stLFPprobe = NaN(Nneurons, length(trange), numel(lfpelecid));
        stCSDprobe = NaN(Nneurons, length(trange), numel(csdelectinds));
        stTFRprobe = NaN(Nneurons, length(trange), numel(fVec));
        % ~2000 units per session, 7 seconds per neuron, ~1 day per session. too long. choose neurons to do this with.
        % ~200 V1 units per session, 7 seconds per neuron, 140 min per session. 
        for ii = 1:Nneurons 
        % tic
            tempspkinds = find(spiketraintrimmed(:,ii));
            % Ncutspks = 10000;
            % if numel(tempspkinds)>Ncutspks % randomly pick Ncutspks so that code does not run out of memory                
            %     cutspks = randperm(tempNspikes, Ncutspks);
            %     tempspkinds = tempspkinds(cutspks);
            % end

            tempNspikes = numel(tempspkinds);
            tempstinds = tempspkinds+trange;
            
            tempstlfp = NaN( length(trange), numel(lfpelecid) );
            for e = 1:numel(lfpelecid)
                templfp = lfpblock(e,:);
                tempstlfp(:,e) = mean(templfp(tempstinds),1);
            end

            tempstcsd = NaN( length(trange), numel(csdelectinds) );
            for e = 1:numel(csdelectinds)
                tempcsd = csdblock(e,:);
                tempstcsd(:,e) = mean(tempcsd(tempstinds),1);
            end

            tempsttfr = NaN( length(trange), numel(fVec) );
            for e = 1:numel(fVec)
                temptfr = TFR_L23_block(e,:);
                tempsttfr(:,e) = mean(temptfr(tempstinds), 1);
            end

            stLFPprobe(ii,:,:) = tempstlfp;
            stCSDprobe(ii,:,:) = tempstcsd;
            stTFRprobe(ii,:,:) = tempsttfr;
        % toc
        end
        save( sprintf('%sV1spiketriggered_LFP_CSD_TFR_probe%s.mat', pathpp, probes{iprobe}), ...
            'neuindV1', 'stLFPprobe', 'stCSDprobe', 'stTFRprobe', '-v7.3')
        toc(probeclk)
    end

    toc(sesclk)
end
