classdef SpecExpmt < handle
	properties
		brukerObj;
        expmtNum;
        rawData;
		data;
        phasing = [0,0]; %0th,1st order in deg
        phasePivot = 0; %ppm
		nChannels;
		nSpecPts;
		nReps;
		activeViewer = false;
		viewReps = 1;
    end

	events
		dataChange;
    end

	methods
		function obj = SpecExpmt(path)
            addpath(genpath(pwd));
			if nargin > 0
				%try
                    disp(char(path));
					brukerObj = RawDataObject(char(path));
                    pathArr = split(path,"/");
                    num = pathArr(end-3);
                    obj.expmtNum = num{1};
				    obj.brukerObj = brukerObj;
                    obj.data = brukerObj.data{1};
                    obj.rawData = brukerObj.data{1};
                    [obj.nChannels,obj.nSpecPts,obj.nReps] = size(obj.data);
				    addlistener(obj,'dataChange',@handleDataChange);
                    
                %catch err
				%	warning('This package requires Bruker Matlab paths to be loaded by running addBrukerPaths.m from within the pvmatlab folder');
               % end
            end
        end

        function revertData(obj)
            obj.data = obj.rawData;
            notify(obj,'dataChange');
        end

		function showViewer(obj)
			if obj.activeViewer
				notify(obj,'dataChange');
            else
				activate = input('Viewer is not active, would you like to activate? (y/n)','s');
				if strcmp(activate,'y')
					obj.activeViewer = true;
					obj.showViewer;
                end
            end
        end

		function handleDataChange(obj,~)
			if obj.activeViewer
				specFig = findobj('type','figure','name','Spectrum');
				if ~strcmp(get(specFig, 'type'), 'figure')
					specFig = figure('name','Spectrum','position',[713 554 727 243]);
                    xlabel('ppm')
                    ylabel('Signal')
                end

				fidFig = findobj('type','figure','name','FID');
                if ~strcmp(get(fidFig, 'type'), 'figure')
                     	fidFig = figure('name','FID','position',[711 222 727 253]);
                end

				specs = obj.specs;
				fids = obj.fids;
				if length(obj.viewReps)>1
					figure(specFig);
					plot(obj.xppm,real(mean(specs(:,obj.viewReps),2)));
                    figure(fidFig);
                    plot(real(mean(fids(:,obj.viewReps),2)));           
                    
				else
					figure(specFig);
					plot(obj.xppm,real(specs(:,obj.viewReps)));
                    set(gca,'xdir','reverse');
					figure(fidFig);
                    plot(real(fids(:,obj.viewReps)));
                end
            end
        end
		
		function f = fitDNP(obj,ints)
			f = fit(obj.xt',ints','exp1');
        end

		function timeAxis = xt(obj)
			TR = obj.brukerObj.Acqp.ACQ_repetition_time/1000; % TR in seconds
			timeAxis = TR*(1:obj.nReps);
        end

		function flp(obj)
			set(gca,'xdir','reverse');
        end
		
		function natPol = P0(obj,T,B0,nuc)
			arguments
				obj
				T = 295 %K ~ Room temp
				B0 = obj.brukerObj.readVisu.Visu.VisuMagneticFieldStrength
				nuc = obj.brukerObj.readVisu.Visu.VisuMrsResonantNuclei
			end;

			if strcmp(nuc,'13C')
				gamma = 6.73e7; %rad/s/T
			else
				error('Nucleus "%s" is not supported',nuc);
            end

			hbar = 1.05e-34; %Js
			kB = 1.38e-23; %J/T
			natPol = hbar*gamma*B0/(2*kB*T)*100;
        end
	    
		function intsArr = peakInts(obj,specs,intBdsPPM,flipAdjust,decayCorr)
               arguments
                    obj
				    specs
				    intBdsPPM
				    flipAdjust = false %correct integrals using flip ang
                    decayCorr = false %correct for polarization decay from measurements
               end
			xppm = obj.xppm;
			[~,intStartInd] = min(abs(xppm-max(intBdsPPM)));
			[~,intEndInd] = min(abs(xppm-min(intBdsPPM)));
			intsArr = sum(abs(specs((intStartInd:intEndInd),:)),1);

			if flipAdjust
				flipAng = obj.brukerObj.readVisu.Visu.VisuAcqFlipAngle; %deg
				flipAngRad = flipAng*pi/180;	
                disp(flipAng);
				for i = (1:length(intsArr))
                    if flipAng == 0
                        return
                    else
					    intsArr(i) = intsArr(i)/sin(flipAngRad);
                        if decayCorr
                            if flipAng ~= 90
                                intsArr(i) = intsArr(i)/(cos(flipAngRad)^(i-1));
                            end
                        end
                    end
                end
            end
        end
				
		function ppmAxis = xppm(obj,chan)
            arguments
                obj
                chan = 1
            end;
			ppm = obj.brukerObj.Method.PVM_SpecSW; % spectral BW in ppm
			cppm = obj.brukerObj.Method.PVM_FrqWorkPpm(1); % center frequency in ppm
			[dimf,~] = size(obj.fids(chan));
			xppm = (ppm/dimf)*(1:dimf);
			ppmAxis = fliplr(xppm)-(ppm/2-cppm);
        end	
			
        function specArr = specs(obj,chan)
			arguments
                obj
                chan = 1
            end
			fid = obj.fids(chan);
            %[~,pivotInd] = min(abs(obj.xppm-obj.phasePivot));
            pivotInd = obj.phasePivot;
            phase = ((1:length(fid(:,1)))'-pivotInd)*obj.phasing(2)+obj.phasing(1);
			specArr = fftshift((ifft(fid)),1).*exp(1i*deg2rad(phase));
        end

		function fidArr = fids(obj,chan)
			arguments
				obj
				chan = 1
            end
			fidArr = squeeze(obj.data(chan,:,:));
        end 

		function obj =  blank(obj, blankInd)
			arguments
				obj
                blankInd = 0 % => automatic blanking if not specified
            end

			if blankInd<1 %automatic blanking (arb. based on first channel, should all be the same)
				[~,blankInd] = max(abs(obj.data(1,:,1))); %blank based on first scan (most accurate for auto)
            end
			
			for i = (1:obj.nChannels)			
                obj.data(i,1:end-blankInd, :) = obj.data(i,blankInd+1:end, :);
                obj.data(i,(end-blankInd+1):end, :) = 0 + 0i;
            end
			notify(obj,'dataChange');
        end
		
		function obj = lbExp(obj,lb)
			arguments
				obj
				lb = 0 % Hz
			end;
			
			if lb > 0
				ppm = obj.brukerObj.Method.PVM_SpecSW; % spectral BW in ppm
				cf = obj.brukerObj.Method.PVM_FrqRef(1); % working center frequency in MHz
				dimf = obj.brukerObj.Method.PVM_SpecMatrix; % spectral points
				tp = (1/(ppm*cf))*(1:dimf);
				lbf = exp(-lb*tp);
				for i = (1:obj.nChannels)
					obj.data(i,:,:) =  (lbf.*squeeze(obj.data(i,:,:))')';
                end
            end
			notify(obj,'dataChange');
        end
		
		function obj = zf(obj,fillFac)
			arguments
				obj
				fillFac = 1
			end;

			if fillFac>1
				fill = zeros(obj.nChannels,obj.nSpecPts*(fillFac-1),obj.nReps,'like',obj.data);
				obj.data = cat(2,obj.data,fill);
            end
		    notify(obj,'dataChange');
        end  
    end
end
