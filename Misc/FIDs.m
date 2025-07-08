classdef FIDs < handle

    properties
        data
        nPoints
        nReps
        ppmBW = NaN
        ppmCF = NaN
        mhzCF = NaN
        hzBW = NaN
        flipAng = NaN
        dataRaw
        appliedBlanking = NaN;
        appliedLB = NaN;
        appliedZF = NaN;
    end

    events
        processing
    end
    methods
        function obj = FIDs(data,varargin)
            obj.data = data;
            [obj.nPoints,obj.nReps] = size(obj.data);
            obj.dataRaw = data;
            for ind = (1:length(varargin))
                switch string(varargin{ind})
                    case 'hzBW'
                        obj.hzBW = varargin{ind+1};
                    case 'mhzCF'
                        obj.mhzCF = varargin{ind+1};
                    case 'ppmCF'
                        obj.ppmCF = varargin{ind+1};
                    case 'flipAng'
                        obj.flipAng = varargin{ind+1};
                end
            end
            if (~isnan(obj.hzBW)) && (~isnan(obj.mhzCF)) 
                obj.ppmBW = obj.hzBW/obj.mhzCF;
            end
            if anynan([obj.hzBW,obj.mhzCF,obj.ppmCF])
                warning(['Some methods will not be accessable without ' ...
                    'parameters "hzBW", "mhzCF","ppmCF".'])
            end
            addlistener(obj,'processing',@updateProcessing);
        end

        function revert(obj,toRevert)
            arguments
                obj
                toRevert = 'all'
            end
            switch toRevert
                case 'all'
                    obj.appliedBlanking = NaN;
                    obj.appliedLB = NaN;
                    obj.appliedZF = NaN;
                    notify(obj,'processing');
                case 'blank'
                    obj.appliedBlanking = NaN;
                    notify(obj,'processing');
                case 'lb'
                    obj.appliedLB = NaN;
                    notify(obj,'processing');
                case 'zf'
                    obj.appliedZF = NaN;
                    notify(obj,'processing');
                otherwise
                    warning('Not a valid revert request!');
            end
        end
                    
        function updateProcessing(obj,~)
            obj.data = obj.dataRaw;
            if ~isnan(obj.appliedBlanking)
                blankInd = obj.appliedBlanking;
                obj.data(1:end-blankInd, :) = obj.data(blankInd+1:end, :);
                obj.data((end-blankInd+1):end, :) = 0 + 0i;
            end
            if ~isnan(obj.appliedLB)
                for rep = (1:obj.nReps)
                    obj.data(:,rep) =  (obj.appliedLB.*obj.data(:,rep)')';
                end
            end
            if ~isnan(obj.appliedZF)
				fill = zeros(obj.nPoints*(obj.appliedZF-1), ...
                    obj.nReps,'like',obj.data);
				obj.data = cat(2,obj.data,fill);
            end
            [obj.nPoints,obj.nReps] = size(obj.data);
        end    

        function obj =  blank(obj, blankInd)
			arguments
				obj
                blankInd = NaN % => automatic blanking if not specified
            end
            if isnan(obj.appliedBlanking)
                if isnan(blankInd)
                    blankInd = obj.nPoints; %check this!!
                    for rep = (1:obj.nReps)
                        [~,localBlank] = max(abs(obj.data(:,rep)));
                        if localBlank<blankInd
                            blankInd = localBlank;
                        end
                    end
                end	
                obj.appliedBlanking = blankInd;
			    notify(obj,'processing');
            end
        end
		
		function obj = lbExp(obj,lb)
			arguments
				obj
				lb = NaN % Hz
			end;
            if anynan([obj.ppmBW,obj.mhzCF])
                error("Missing parameters: 'ppmBW' and 'mhzCF' required" + ...
                    "for line broadening");
            end
			
            if ~isnan(lb)
                tp = (1/(obj.ppmBW*obj.mhzCF))*(1:length(obj.dataRaw(:,1)));
				obj.appliedLB = exp(-lb*tp);
            end
			notify(obj,'processing');
        end
		
		function obj = zf(obj,fillFac)
			arguments
				obj
				fillFac = 1
			end;
            obj.appliedZF = fillFac;
		    notify(obj,'processing');
        end

        function spec = getSpecs(obj)
            specPts = fftshift((ifft(obj.data)),1);
            spec = Spectra(specPts,'mhzCF',obj.mhzCF,'ppmCF', ...
                obj.ppmCF,'hzBW',obj.hzBW,'flipAng',obj.flipAng);
        end
    end
end