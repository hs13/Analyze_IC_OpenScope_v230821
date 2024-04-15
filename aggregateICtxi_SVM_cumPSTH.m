datadir = 'S:\OpenScopeData\00248_v240130\';
nwbdir = dir(datadir);
nwbsessions = {nwbdir.name};
nwbsessions = nwbsessions( contains(nwbsessions, 'sub-') | contains(nwbsessions, 'sub_') );
Nsessions = numel(nwbsessions);

Twin = 5;
neuopt = 'RS';
svmdesc = 'trainICRC';
preproc = 'zscore'; % '' is z-score train trials, '_zscoreall', or '_meancenter'
whichSVMkernel = 'Linear';

pathsv = [datadir 'SVM_' svmdesc '_selectareas' filesep];
whichICblock = 'ICwcfg1';
whichblock = [whichICblock '_presentations'];
visareas = {'VISp', 'VISl', 'VISrl', 'VISal', 'VISpm', 'VISam'};

switch svmdesc
    case 'trainICRC'
        traintrialtypes = [106, 107, 110, 111];
        probetrialtypes = [1105, 1109];
    case 'trainREx'
        traintrialtypes = [1201, 1299];
        probetrialtypes = [106, 107, 110, 111];
    otherwise
        error([svmdesc ' not recognized'])
end

SVMtrainICRCcumpsthagg = struct();
testlabelfinalagg = struct();
testscorecumpsthagg = struct();
normtestscorecumpsthagg = struct();
Tmilestonesagg = struct();

for ises = 1:Nsessions
    tic
    pathsvm = [pathsv nwbsessions{ises} filesep];

    for a = 1:numel(visareas)
        clearvars SVMcumpsth
        whichvisarea = visareas{a};
        svmcumpsthfn = [pathsvm, 'SVMcumpsth' num2str(Twin) 'ms_', svmdesc, '_', whichvisarea, neuopt, '_', whichSVMkernel, '_', preproc, '_', whichICblock, '.mat'];
        if exist(svmcumpsthfn, 'file')
            load(svmcumpsthfn)
            SVMtrainICRCcumpsthagg(ises).(whichvisarea) = SVMcumpsth;
        else
            SVMtrainICRCcumpsthagg(ises).(whichvisarea) = [];
        end
    end

    cumpsthtl = SVMtrainICRCcumpsthagg(ises).VISp.psthbinTends;
    [ttindsordered,~]=sort(SVMtrainICRCcumpsthagg(ises).VISp.testtrialinds(:));
    testtrialstt = SVMtrainICRCcumpsthagg(ises).VISp.trialorder(ttindsordered);
    for a = 1:numel(visareas)
        whichvisarea = visareas{a};
        if isempty(SVMtrainICRCcumpsthagg(ises).(whichvisarea))
            continue
        end
        finallabel = squeeze(SVMtrainICRCcumpsthagg(ises).(whichvisarea).label(end,:,:));

        Ntesttrials = size(SVMtrainICRCcumpsthagg(ises).(whichvisarea).testtrialinds,1);
        Nsplits = size(SVMtrainICRCcumpsthagg(ises).(whichvisarea).testtrialinds,2);
        origtestlabel = NaN(length(cumpsthtl), Ntesttrials, Nsplits);
        origtestscore = NaN(length(cumpsthtl), Ntesttrials, Nsplits);
        for isplit = 1:Nsplits
            testtrialinds = SVMtrainICRCcumpsthagg(ises).(whichvisarea).testtrialinds(:,isplit);
            origtestlabel(:,:,isplit) = SVMtrainICRCcumpsthagg(ises).(whichvisarea).label(:,testtrialinds,isplit);
            for itt = 1:numel(traintrialtypes)
                temptrials = finallabel(testtrialinds,isplit)==traintrialtypes(itt);
                origtestscore(:,temptrials,isplit) = squeeze(SVMtrainICRCcumpsthagg(ises).(whichvisarea).score(:,testtrialinds(temptrials),itt,isplit));
            end
        end
        origtestlabel = reshape(origtestlabel, length(cumpsthtl), Ntesttrials*Nsplits);
        origtestscore = reshape(origtestscore, length(cumpsthtl), Ntesttrials*Nsplits);

        finaltestlabel = origtestlabel(end,:);

        [tti,testtrialord]=sort(SVMtrainICRCcumpsthagg(ises).(whichvisarea).testtrialinds(:));
        if ~isequal(ttindsordered, tti)
            error('test trial set different for every area?')
        end
        testlabelfinalagg(ises).(whichvisarea) = finaltestlabel(testtrialord);
        testscorecumpsthagg(ises).(whichvisarea) = origtestscore(:,testtrialord);
    end

    for a = 1:numel(visareas)
        whichvisarea = visareas{a};
        if isempty(SVMtrainICRCcumpsthagg(ises).(whichvisarea))
            continue
        end
        tempts = testscorecumpsthagg(ises).(whichvisarea);
        normtestscorecumpsthagg(ises).(whichvisarea) = (tempts-tempts(1,:))./(tempts(end,:)-tempts(1,:));
    end

    milestonesvec = [0.25; 0.50; 0.75];
    for a = 1:numel(visareas)
        whichvisarea = visareas{a};
        if isempty(SVMtrainICRCcumpsthagg(ises).(whichvisarea))
            continue
        end
        tempnorm = normtestscorecumpsthagg(ises).(whichvisarea);
        Nalltest = size(tempnorm,2);
        Tmilestonesagg(ises).(whichvisarea) = NaN(length(milestonesvec), Nalltest);
        for t = 1:length(milestonesvec)
            % first timepoint to cross milestone
            [~,mi]=max(tempnorm>=milestonesvec(t),[],1);
            % v50 = tempnorm(sub2ind(size(tempnorm), mi, 1:size(tempnorm,2)));
            % v49 = tempnorm(sub2ind(size(tempnorm), mi-1, 1:size(tempnorm,2)));
            % if ~all(v50>=0.5 & v49<0.5)
            %     error('check mi')
            % end
            Tmilestonesagg(ises).(whichvisarea)(t,:) = cumpsthtl(mi);
        end
        if ~isequal(sort(Tmilestonesagg(ises).(whichvisarea),1), Tmilestonesagg(ises).(whichvisarea))
            error('Tmilestones does not follow order -- check algorithm')
        end
    end
    toc
end

save([pathsv 'SVMcumpsth' num2str(Twin) 'ms_', svmdesc '_' neuopt 'agg.mat'], 'SVMtrainICRCcumpsthagg', ...
    'testlabelfinalagg', 'testscorecumpsthagg', 'normtestscorecumpsthagg', 'Tmilestonesagg', '-v7.3')

%% check correspondence between SVMall and final timepoint of SVMcumpsthall
SVMcumpsthall = SVMtrainICRCcumpsthagg(ises);
pathsvm = [pathsv nwbsessions{ises} filesep];

SVMall = struct();
for a = 1:numel(visareas)
    clearvars SVMtrainICRC SVMtrainREx
    whichvisarea = visareas{a};
    load([pathsvm, 'SVM_', svmdesc, '_', whichvisarea, '_', whichSVMkernel, '_', preproc, '_', whichICblock, '.mat'])
    switch svmdesc
        case 'trainICRC'
            SVMall.(whichvisarea) = SVMtrainICRC;
        case 'trainREx'
            SVMall.(whichvisarea) = SVMtrainREx;
        otherwise
            error([svmdesc ' not recognized'])
    end
end

whichvisarea = 'VISp';
figure; plot(SVMall.(whichvisarea).spkcnt.all.score(:), reshape( SVMcumpsthall.(whichvisarea).score(end,:,:,:),[],1), '.')

[sv,si]=max(SVMall.(whichvisarea).spkcnt.all.score,[],2);
temp = squeeze(traintrialtypes(si));
temp1 = SVMall.(whichvisarea).spkcnt.all.label;
isequal( squeeze(traintrialtypes(si)), SVMall.(whichvisarea).spkcnt.all.label)

isequal(SVMall.(whichvisarea).spkcnt.traintrialinds, SVMcumpsthall.(whichvisarea).traintrialinds)
isequal(SVMall.(whichvisarea).spkcnt.testtrialinds, SVMcumpsthall.(whichvisarea).testtrialinds)

%% compare score between correct vs incorrect trials
% incorrect trials do have lower scores, but the distribution is not
% exactly separate
SVMcumpsthall = SVMtrainICRCcumpsthagg(ises);
whichvisarea = 'VISp';

testtrialtypes = SVMcumpsthall.(whichvisarea).trialorder(SVMcumpsthall.(whichvisarea).testtrialinds);
Nsplits = size(testtrialtypes,2);
testlabel = NaN(size(testtrialtypes));
testscore = NaN(size(testtrialtypes));
for isplit = 1:Nsplits
    testtrialinds = SVMcumpsthall.(whichvisarea).testtrialinds(:,isplit);
    testlabel(:,isplit) = squeeze( SVMcumpsthall.(whichvisarea).label(end,testtrialinds,isplit) );
    tempscore = squeeze( SVMcumpsthall.(whichvisarea).score(end,testtrialinds,:,isplit) );
    [sv,si]=max(tempscore,[],2);
    testscore(:,isplit) = squeeze(sv);
end
figure;
hold all
histogram(testscore(testlabel==testtrialtypes))
histogram(testscore(testlabel~=testtrialtypes))

%% IC test trials
% first, focus on V1 and LM, and on trials where both areas' decoders had correct predictions
itt =1;
figure
for a = 1:numel(visareas)
    whichvisarea = visareas{a};
    trialsoi = testtrialstt==traintrialtypes(itt);
    subplot(1,numel(visareas),a)
    imagesc(cumpsthtl,1:nnz(trialsoi), testscorecumpsthagg(ises).(whichvisarea)(:,trialsoi)')
    colorbar
end

% check that reordering went well
Ntt2p = 4;
tt2p = randperm(length(testtrialstt),Ntt2p);
figure
for a = 1:numel(visareas)
    whichvisarea = visareas{a};
    for t = 1:Ntt2p
        itrial = tt2p(t);
        subplot(Ntt2p, numel(visareas), (t-1)*numel(visareas)+a)
        hold all
        plot(cumpsthtl, testscorecumpsthagg(ises).(whichvisarea)(:,itrial), 'k--', 'linewidth', 1)
        [r,c]=find(SVMtrainICRCcumpsthagg(ises).(whichvisarea).testtrialinds==ttindsordered(itrial));
        tempcumpsth = squeeze(SVMtrainICRCcumpsthagg(ises).(whichvisarea).score(:,ttindsordered(itrial),:,c));
        plot(cumpsthtl, tempcumpsth)
        title(sprintf('%s test trial #%d', whichvisarea, itrial))
    end
end

whichvisareaA = 'VISp';
whichvisareaB = 'VISal';
trialsoind = find( testtrialstt==traintrialtypes(itt) & ...
    testlabelfinalagg(ises).(whichvisareaA)==traintrialtypes(itt) & testlabelfinalagg(ises).(whichvisareaB)==traintrialtypes(itt) );

% example trials
figure
for ii = 1:12
    subplot(3,4,ii)
    hold all
    plot(cumpsthtl, normtestscorecumpsthagg(ises).(whichvisareaA)(:,trialsoind(ii)))
    plot(cumpsthtl, normtestscorecumpsthagg(ises).(whichvisareaB)(:,trialsoind(ii)))
end

% average across trials
figure
for itt = 1:numel(traintrialtypes)
    trialsoind = find( testtrialstt==traintrialtypes(itt) & ...
        testlabelfinalagg(ises).(whichvisareaA)==traintrialtypes(itt) & testlabelfinalagg(ises).(whichvisareaB)==traintrialtypes(itt) );
    subplot(2,2,itt)
    hold all
    shadedErrorBar(cumpsthtl, mean(normtestscorecumpsthagg(ises).(whichvisareaA)(:,trialsoind),2), ...
        std(normtestscorecumpsthagg(ises).(whichvisareaA)(:,trialsoind),0,2)/sqrt(numel(trialsoind)), {'Color', 'b', 'LineWidth', 2},1)
    shadedErrorBar(cumpsthtl, mean(normtestscorecumpsthagg(ises).(whichvisareaB)(:,trialsoind),2), ...
        std(normtestscorecumpsthagg(ises).(whichvisareaB)(:,trialsoind),0,2)/sqrt(numel(trialsoind)), {'Color', 'r', 'LineWidth', 2},1)
    title(traintrialtypes(itt))
end

% COMPARE DYNAMICS OF TWO PAREAS TRIAL-BY-TRIAL: test trials, when both areas had the *correct* prediction
% find the first timepoint at which normtestscorecumpsth crosses
% 0.25, 0.5, 0.75 (called T25, T50, T75 respsectively)
% divide into 6 trial types
% 1. areaA ramping starts earlier and finishes later than area B
% 2. areaB ramping starts earlier and finishes later than area A
% 3. areaA faster than areaB if all three timeponts (T25, T50, T75) are earlier for A than B
% 4. areaB faster than areaA if all three timeponts (T25, T50, T75) are earlier for A than B
% 5. simultaneous: all three timeponts are identical
% 6. crisscrossing if T25 and T75 go in one direction and T50 goes in the opposite direction
dynamicslabels = 0:6;
comparedynamicsprob = struct();
for ab = 1:2
    switch ab
        case 1
            whichvisareaA = 'VISp';
            whichvisareaB = 'VISl';
        case 2
            whichvisareaA = 'VISp';
            whichvisareaB = 'VISal';
        otherwise
            error('specify whichvisareaA and whichvisareaB')
    end
    ABfield = [whichvisareaA '_' whichvisareaB];
    comparedynamicsprob.(ABfield) = zeros(numel(traintrialtypes), length(dynamicslabels), Nsessions);
    for ises = 1:Nsessions
        if isempty(Tmilestonesagg(ises).(whichvisareaA)) || isempty(Tmilestonesagg(ises).(whichvisareaB))
            comparedynamicsprob.(ABfield)(:,:,ises) = NaN;
            continue
        end
        Ntestall = size(normtestscorecumpsthagg(ises).(whichvisareaA),2);
        comparedynamics = NaN(1,Ntestall);
        for dyn = 1:6
            switch dyn
                case 1
                    trialsinclass = Tmilestonesagg(ises).(whichvisareaA)(1,:)<=Tmilestonesagg(ises).(whichvisareaB)(1,:) ...
                        & Tmilestonesagg(ises).(whichvisareaA)(3,:)>=Tmilestonesagg(ises).(whichvisareaB)(3,:);
                case 2
                    trialsinclass = Tmilestonesagg(ises).(whichvisareaA)(1,:)>=Tmilestonesagg(ises).(whichvisareaB)(1,:) ...
                        & Tmilestonesagg(ises).(whichvisareaA)(3,:)<=Tmilestonesagg(ises).(whichvisareaB)(3,:);
                case 3
                    trialsinclass = all(Tmilestonesagg(ises).(whichvisareaA)<=Tmilestonesagg(ises).(whichvisareaB),1);
                case 4
                    trialsinclass = all(Tmilestonesagg(ises).(whichvisareaA)>=Tmilestonesagg(ises).(whichvisareaB),1);
                case 5
                    trialsinclass = all(Tmilestonesagg(ises).(whichvisareaA)==Tmilestonesagg(ises).(whichvisareaB),1);
                case 6
                    temp = Tmilestonesagg(ises).(whichvisareaA)>Tmilestonesagg(ises).(whichvisareaB);
                    trialsinclass = temp(1,:)==~temp(2,:) & temp(3,:)==~temp(2,:);
            end
            comparedynamics(trialsinclass) = dyn;
        end

        for itt = 1:numel(traintrialtypes)
            trialsoind = find( testtrialstt==traintrialtypes(itt) & ...
                testlabelfinalagg(ises).(whichvisareaA)==traintrialtypes(itt) & testlabelfinalagg(ises).(whichvisareaB)==traintrialtypes(itt) );
            [v,c]=uniquecnt(comparedynamics(trialsoind));
            % disp([v',c'])
            comparedynamicsprob.(ABfield)(itt, ismember(dynamicslabels,v), ises) = c/numel(trialsoind);
        end
    end
end

figure
for ab = 1:2
    switch ab
        case 1
            whichvisareaA = 'VISp';
            whichvisareaB = 'VISl';
        case 2
            whichvisareaA = 'VISp';
            whichvisareaB = 'VISal';
        otherwise
            error('specify whichvisareaA and whichvisareaB')
    end
    ABfield = [whichvisareaA '_' whichvisareaB];
for itt = 1:numel(traintrialtypes)
    subplot(2,numel(traintrialtypes),(ab-1)*numel(traintrialtypes)+itt)
imagesc(squeeze(comparedynamicsprob.(ABfield)(itt,:,:))')
set(gca,'Xtick',1:length(dynamicslabels), 'XtickLabel', dynamicslabels)
title(sprintf('%s vs %s Trial %d', whichvisareaA, whichvisareaB, traintrialtypes(itt) ))
colorbar
end
end
colormap redblue

% compare ramp time: longer means slower
% calculate AUROC for rampA vs rampB for each session, then see if the
% distribution is significantly different from 0.5 across sessions
rampA = Tmilestonesagg(ises).(whichvisareaA)(3,:)-Tmilestonesagg(ises).(whichvisareaA)(1,:);
rampB = Tmilestonesagg(ises).(whichvisareaB)(3,:)-Tmilestonesagg(ises).(whichvisareaB)(1,:);
figure; hold all
plot(rampA(trialsoind), rampB(trialsoind), 'o')
xl = xlim;
plot(xl,xl, '-')
p = signrank(rampA(trialsoind), rampB(trialsoind));
fprintf('ramp delay (ms) %d trials %s vs %s p=%.4f\n', traintrialtypes(itt), ...
    whichvisareaA, whichvisareaB, p)
fprintf('median: %.2f vs %.2f, mean: %.2f vs %.2f\n', ...
    median(rampA(trialsoind)), median(rampB(trialsoind)), ...
    mean(rampA(trialsoind)), mean(rampB(trialsoind)))


T50A = Tmilestonesagg(ises).(whichvisareaA)(2,:);
T50B = Tmilestonesagg(ises).(whichvisareaB)(2,:);
figure; hold all
plot(T50A(trialsoind), T50B(trialsoind), 'o')
xl = xlim;
plot(xl,xl, '-')
p = signrank(T50A(trialsoind), T50B(trialsoind));
fprintf('T50 %d trials %s vs %s p=%.4f\n', traintrialtypes(itt), whichvisareaA, whichvisareaB, p)
fprintf('median: %.2f vs %.2f, mean: %.2f vs %.2f\n', ...
    median(T50A(trialsoind)), median(T50B(trialsoind)), ...
    mean(T50A(trialsoind)), mean(T50B(trialsoind)))

