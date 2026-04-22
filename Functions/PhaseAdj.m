classdef PhaseAdj < handle
    properties
        ax;
        phi0_knob;
        phi1_knob;
        pivot_slider;
        panel;
        specData;
        specHandle = gobjects(1);
        ppmAx;
        hzAx;
        specAxSetting = 'ind';
        phi0;
        phi1;
        pivot;
        phi0_incBtn;
        phi0_decBtn;

        phi1_incBtn;
        phi1_decBtn;
    end

    properties (Dependent)
        specAx;
        currPhase;
    end


    methods

        function sAx = get.specAx(obj)
            indAx = 1:numel(obj.specData);
            switch obj.specAxSetting
                case 'ind'
                    sAx = indAx;
                case 'ppm'
                    if isempty(obj.ppmAx)
                        warning('Unable to use ppm axis, reverting to index.')
                        obj.specAxSetting = 'ind';[]
                        sAx = indAx;
                    else
                        sAx = obj.ppmAx;
                    end
                case 'hz'
                    if isempty(obj.hzAx)
                        warning('Unable to use hz axis, reverting to index.')
                        obj.specAxSetting = 'ind';
                        sAx = indAx;
                    else
                        sAx = obj.hzAx;
                    end
            end
        end

        function set.specAxSetting(obj,val)
            assert(ismember(val,{'ind','ppm','hz'}),'ERROR: invalid axes setting. Must be: "ind", "ppm", or "hz"');
            obj.specAxSetting = val;
            
        end

        function inds = ppm2ind(obj,vals)
            if isempty(obj.ppmAx)
                inds = [];
                return
            end
            inds = zeros(size(vals));
            for ind = 1:numel(vals)
                [~,idx] = min(abs(obj.ppmAx-vals(ind)));
                inds(ind) = idx;
            end
        end

        function inds = hz2ind(obj,vals)
            if isempty(obj.hzAx)
                inds = [];
                return
            end
            inds = zeros(size(vals));
            for ind = 1:numel(vals)
                [~,idx] = min(abs(obj.hzAx-vals(ind)));
                inds(ind) = idx;
            end
        end

        function phase = get.currPhase(obj)
            pivotInd = obj.pivot;
            switch obj.specAxSetting
                case 'ind'
                    %do nothing
                case 'ppm'
                    pivotInd = obj.ppm2ind(obj.pivot);
                case 'hz'
                    pivotInd = obj.hz2ind(obj.pivot);
            end

            if isempty(obj.phi0)
                phase = repmat(obj.phi0,length(obj.specData),1);
            else
                phase = ((1:length(obj.specData))'-pivotInd)*obj.phi1+obj.phi0;
            end
        end

        function updatePlot(obj)
            newSpecAx = obj.specAx;
            psData = obj.specData(:).*exp(1i*deg2rad(obj.currPhase(:)));
            if ~isvalid(obj.specHandle)
                obj.specHandle = plot(obj.ax,real(psData));
            else
                obj.specHandle.YData = real(psData);
            end
            obj.specHandle.XData = newSpecAx;
        end

        function knobChange(obj,src,~)
            switch src.Tag
                case 'phi0_knob'
                    obj.phi0 = src.Value;
                case 'phi1_knob'
                    obj.phi1 = src.Value;
            end
            obj.updatePlot;
        end

        function precisionButtons(obj,src,~)
            phi0_ticks = obj.phi0_knob.MinorTicks;
            phi0_precision = phi0_ticks(2)-phi0_ticks(1);
            phi1_ticks = obj.phi1_knob.MinorTicks;
            phi1_precision = phi1_ticks(2)-phi1_ticks(1);
            switch src.Tag
                case 'phi0_incBtn'
                    newPhi0Ticks = phi0_ticks(1):phi0_precision/10:phi0_ticks(end);
                    set(obj.phi0_knob,'MinorTicks',newPhi0Ticks);
                case 'phi0_decBtn'
                    newPhi0Ticks = phi0_ticks(1):phi0_precision*10:phi0_ticks(end);
                    set(obj.phi0_knob,'MinorTicks',newPhi0Ticks);
                case 'phi1_incBtn'
                    newPhi1Ticks = phi1_ticks(1):phi1_precision/10:phi1_ticks(end);
                    set(obj.phi1_knob,'MinorTicks',newPhi1Ticks);
                case 'phi1_decBtn'
                    newPhi1Ticks = phi1_ticks(1):phi1_precision*10:phi1_ticks(end);
                    set(obj.phi1_knob,'MinorTicks',newPhi1Ticks);
            end
        end


        function obj = PhaseAdj(specData,opts)
            arguments
                specData (1,:) %1D spectral data (complex)
                opts.parent = [] %panel handle to embed phasing window
                opts.ppmAx = [];
                opts.hzAx = [];
            end
            obj.specData = specData;
            obj.panel = opts.parent;
            obj.ppmAx = opts.ppmAx;
            obj.phi0 = 0;
            obj.phi1 = 0;
            obj.pivot = 1;
            if ~isempty(obj.ppmAx)
                assert(isequal(numel(obj.ppmAx),numel(specData)),'ERROR: ppm axis values does not match number of spectral points');
            end
            
            obj.hzAx = opts.hzAx;
            if ~isempty(obj.hzAx)
                assert(isequal(numel(obj.hzAx),numel(specData)),'ERROR: hz axis values does not match number of spectral points');
            end
            if isempty(obj.panel)
                fig = uifigure;
                obj.panel = uipanel(fig);
                obj.panel.Units = 'normalized';
                obj.panel.Position = [0,0,1,1];
            end
            grid = uigridlayout(obj.panel,"ColumnWidth",{'4x','1x','1x'},...
                                      "RowHeight",{'3x','3x','1x','3x','1x'});
            obj.ax = uiaxes(grid);
            obj.ax.Layout.Row = [1,4];
            obj.ax.Layout.Column = 1;
            obj.ax.XDir = 'reverse';

            obj.specHandle = plot(obj.ax,real(specData));
            obj.phi0_knob = uiknob(grid,"Limits",[-180,180], ...
                                        "Value",0, ...
                                        'ValueChangedFcn',@(src,evt) obj.knobChange(src,evt),...
                                        'Tag','phi0_knob');
            obj.phi0_knob.Layout.Row = 2;
            obj.phi0_knob.Layout.Column = [2,3];
            
            obj.phi0_incBtn = uibutton(grid,'push','Text', ...
                                            '+', ...
                                            'tag', 'phi0_incBtn',...
                                            'ButtonPushedFcn',@(src,evt) obj.precisionButtons(src,evt));
            obj.phi0_incBtn.Layout.Row = 3;
            obj.phi0_incBtn.Layout.Column = 3;

            obj.phi0_decBtn = uibutton(grid,'push','Text', ...
                                            '-', ...
                                            'tag', 'phi0_decBtn',...
                                            'ButtonPushedFcn',@(src,evt) obj.precisionButtons(src,evt));
            obj.phi0_decBtn.Layout.Row = 3;
            obj.phi0_decBtn.Layout.Column = 2;
            
            
            obj.phi1_knob = uiknob(grid,"Limits",[-10,10], ...
                                        "Value",0, ...
                                        'ValueChangedFcn',@(src,evt) obj.knobChange(src,evt),...
                                        'Tag','phi1_knob');
            obj.phi1_knob.Layout.Row = 4;
            obj.phi1_knob.Layout.Column = [2,3];
            
            
            obj.phi1_incBtn = uibutton(grid,'push','Text', ...
                                            '+', ...
                                            'tag', 'phi1_incBtn',...
                                            'ButtonPushedFcn',@(src,evt) obj.precisionButtons(src,evt));
            obj.phi1_incBtn.Layout.Row = 5;
            obj.phi1_incBtn.Layout.Column = 3;

            obj.phi1_decBtn = uibutton(grid,'push','Text', ...
                                            '-', ...
                                            'tag', 'phi1_decBtn',...
                                            'ButtonPushedFcn',@(src,evt) obj.precisionButtons(src,evt));
            obj.phi1_decBtn.Layout.Row = 5;
            obj.phi1_decBtn.Layout.Column = 2;

            %[spec_min,spec_max] = bounds(obj.specAx);

            % obj.pivot_slider = uislider(obj.panel,'Limits',[spec_min,spec_max]);
            % axPos = obj.ax.InnerPosition;
            % obj.pivot_slider.Position([1,2,3]) = axPos([1,2,3]);
            % obj.pivot_slider.Position(2) = obj.pivot_slider.Position(2)+10;
            

        end
    
    
    end

end