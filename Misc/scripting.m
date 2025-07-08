study = BrukerStudy(fullfile('../../../Partners HealthCare Dropbox/Sam Calos/Yen_Hardy/Hyper/4.7T/Projects/HFpEF Rats/2022/HP13C_data/20220128_1-1/'));
report = Report;
csi = study.getExpmtByNum(7);
csiK = KSpace(csi.procData,'params',csi.params);
fig = figure;
csiK.showWindows(fig,'csi');
csiK.blank(3);
csiK.lbExp(50);
csiK.zf([2,3,3]);
recon = BrukerRecon(flash.seqData);
recon.show
recon.setLayer(maskM);
report.add('figs',{'csi_proc',fig},'notes','CSI fIndex of 513 corresponds to c1pyr peak.');
report.add('notes','mask matches flash slice 7. This slice is used for overlays');
maskedFdata = mask(csiK.fData,maskM,2);
report.add('notes','CSI fIndex of 480 used for initial overlays corresponds to pyr peak');
spec = Spectra(squeeze(sum(sum(maskedFdata,2),3)),'params',csi.params);
main = axes(figure);
spec.linkPlot(main,'plotType','plot','plotMode','real');
aux = axes(figure);
spec.linkPlot(aux,'plotType','plot','plotMode','abs');
report.add('figs',{'real_spec_in_ROI',main.Parent,'abs_spec_in_ROI',aux.Parent},'notes','abs and real spectra. summed over spatial domains after maskM has been applied');
spec.interactivePhase;
spec.baseline;
report.add('figs',{'rep1_phased_baseline',main.Parent},'notes','spec from within roi phased and baselined','procParams',spec.procParams);
pBds = [177.4,171.1];
bBds = [165.4,163.4];
lBds = [185.2,189.1];
report.add('notes','rep1 int Bds:pBds = [177.4,171.1], bBds = [165.4,163.4], lBds = [185.2,189.1]');
pInts = peakInts(spec,pBds,'ppm','real',true,false);
bInts = peakInts(spec,bBds,'ppm','real',true,false);
lInts = peakInts(spec,lBds,'ppm','real',true,false);
pInts(spec.viewReps)
bInts(spec.viewReps)
lInts(spec.viewReps)
spec.revert('baseline');
spec.viewReps = 2;
spec.baseline
report.add('notes','rep2 bds same as rep1');
pInts = peakInts(spec,pBds,'ppm','real',true,false);
bInts = peakInts(spec,bBds,'ppm','real',true,false);
lInts = peakInts(spec,lBds,'ppm','real',true,false);
pInts(spec.viewReps)
bInts(spec.viewReps)
lInts(spec.viewReps)
spec.revert('baseline');
spec.viewReps = 3;
spec.baseline
spec.baseline(false);
report.add('notes','rep3 bds same as rep1');
pInts = peakInts(spec,pBds,'ppm','real',true,false);
bInts = peakInts(spec,bBds,'ppm','real',true,false);
lInts = peakInts(spec,lBds,'ppm','real',true,false);
pInts(spec.viewReps)
bInts(spec.viewReps)
lInts(spec.viewReps)
spec.viewReps = 4;
spec.revert('baseline');
spec.baseline
report.add('notes','rep4 bds same as rep1');
pInts = peakInts(spec,pBds,'ppm','real',true,false);
bInts = peakInts(spec,bBds,'ppm','real',true,false);
lInts = peakInts(spec,lBds,'ppm','real',true,false);
pInts(spec.viewReps)
bInts(spec.viewReps)
lInts(spec.viewReps)
save(fullfile(report.reportDir,'Report.mat'),'spec','study','csiK','csi','maskedFdata','pBds','lBds','bBds');