classdef RealSpace < handle

    properties
        data = NaN
        specs = NaN
        nPoints
        dimX
        dimY
        dimZ
        nReps
        sysParams = struct
        analysis = {};
        
    end

    events
        processing
    end

    methods
        function obj = RealSpace(data,varargin)
            obj.data = data; % nPoints x X x Y x Z x nFrames
            [obj.nPoints,obj.dimX,obj.dimY,obj.dimZ,obj.nReps] = size(data);
            obj.specs = cell(obj.dimX,obj.dimY,obj.dimZ);
            for ind = (1:length(varargin))
               try
                   name = string(varargin{ind});
               catch
                   continue
               end
               switch name
                   case 'params'
                       obj.sysParams = varargin{ind+1};
                   case 'hzBW'
                       obj.sysParams.hzBW = varargin{ind+1};
                   case 'mhzCF'
                       obj.sysParams.mhzCF = varargin{ind+1};
                   case 'ppmCF'
                       obj.sysParams.ppmCF = varargin{ind+1};
                   case 'flipAng'
                       obj.sysParams.flipAng = varargin{ind+1};
                   case 'TR'
                       obj.sysParams.TR = varargin{ind+1};
               end
            end
            if isfield(obj.sysParams,'hzBW') && isfield(obj.sysParams,'mhzCF')
                obj.sysParams.ppmBW = obj.sysParams.hzBW/obj.sysParams.mhzCF;
            end
            supressWarnings = false;
            varargin{end+1} = 'supressWarnings';

            if ~isfield(obj.sysParams,'hzBW') ||...
               ~isfield(obj.sysParams,'mhzCF')||...
               ~isfield(obj.sysParams,'ppmCF')

                warning(['Some methods will not be accessable without ' ...
                    'parameters "hzBW", "mhzCF","ppmCF".'])
                supressWarnings = true;
            end
            varargin{end+1} = supressWarnings;
            
            for x = (1:obj.dimX)
                for y = (1:obj.dimY)
                    for z = (1:obj.dimZ)
                        obj.specs{x,y,z} = Spectra(squeeze(obj.data(:,x,y,z,:)), ...
                            'params',obj.sysParams);
                    end
                end
            end
        end

        function updateData(obj)
            for x = (1:obj.dimX)
                for y = (1:obj.dimY)
                    for z = (1:obj.dimZ)
                        obj.data(:,x,y,z,:) = obj.specs{x,y,z}.data;
                    end
                end
            end
        end

        function revert(obj,toRevert)
            arguments
                obj
                toRevert = 'all'
            end
            if strcmp(toRevert,'all')||...
                strcmp(toRevert,'phase')||...
                strcmp(toRevert,'baseline')
                for x = (1:obj.dimX)
                    for y = (1:obj.dimY)
                        for z = (1:obj.dimZ)
                            obj.specs{x,y,z}.revert(toRevert);
                        end
                    end
                end
            else
                warning('Not a valid revert request!');
            end
        end

        function ints = autoInts(obj,bds,bdsType,noiseThresh,reps)
            tic;
            ints = zeros(size(obj.specs));
            ax = axes(figure);
            count = 0;
            for x = (1:obj.dimX)
                if ~isvalid(ax)
                    return
                else
                    imagesc(ax,ints');
                    title(ax,sprintf('Phased integrals on range [%0.2f, %0.2f]',bds(1),bds(2)))
                end
                %drawnow;
                for y = (1:obj.dimY)
                    for z = (1:obj.dimZ)
                        count = count+1;
                        progress = count/(obj.dimX*obj.dimY*obj.dimZ);
                        if ~isvalid(ax)
                            return
                        else
                            subtitle(ax,sprintf('Progress: %0.f%%',progress*100));
                            drawnow;
                        end
                        summedData = sum(obj.specs{x,y,z}.dataRaw(:,reps),2);
                        if max(max(summedData))==0 && min(min(summedData))==0
                            continue
                        end
                        spec = Spectra(sum(obj.specs{x,y,z}.dataRaw(:,reps),2),'params',obj.sysParams);
                        %spec = obj.specs{x,y,z};
                        int = spec.localAutoProc(bds,bdsType,noiseThresh,adoptProc=false,interpMode='linear');
                        ints(x,y,z) = int;
                        
                    end
                end
            end
            imagesc(ax,ints');
            title(ax,sprintf('Phased integrals on range [%0.2f,%0.2f]',bds(1),bds(2)))

            drawnow;
            obj.analysis{end+1} = struct('ints',ints,'bds',bds,'timeStamp',datetime('now'));
            fprintf('Completed with run time: %0.2f (s)\n',toc);
        end

        function permiate(obj,specX,specY,procParam)
            spec = obj.specs{specX,specY,1};
            for x = (1:obj.dimX)
                for y = (1:obj.dimY)
                    for z = (1:obj.dimZ)
                        if x == specX && y == specY
                            continue
                        end
                        otherSpec = obj.specs{x,y,z};
                        if strcmp(procParam,'all')
                            otherSpec.procParams = spec.procParams;
                        elseif isfield(obj.specs{x,y,z}.procParams,char(procParam))
                            otherSpec.procParams = ...
                                setfield(otherSpec.procParams,char(procParam),...
                                getfield(spec.procParams,char(procParam)));
                        end
                        otherSpec.updateProcessing;
                    end
                end
            end
        end
    end
end