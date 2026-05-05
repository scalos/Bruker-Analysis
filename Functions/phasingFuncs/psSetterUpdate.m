function psSetterUpdate(setter)
    assert(isa(setter,'ProcSetter'));
    psObj = setter.viewerObj;
    dataObj = setter.dataObj;
    procObj = setter.procStep;
    currFoc = dataObj.rFocus;
    prevData = dataObj.getProcStepInput(procObj);
    currFoc(1) = {':'};
    prevData_foc = prevData(currFoc{:});
    prevData_foc = mean(prevData_foc,2:ndims(prevData));
    % phi0s = [];
    % phi1s = [];
    % pivots = [];
    spatFoc = currFoc(2:end);
    if ~procObj.constInRegion(spatFoc)
        psObj.badFocus = 1;
    else
        psObj.badFocus = 0;
        if ~isempty(procObj.params)
            currPhi0s = procObj.params{1};
            currPhi1s = procObj.params{2};
            currPivots = procObj.params{3};
            phi0s = currPhi0s(spatFoc{:});
            phi1s = currPhi1s(spatFoc{:});
            pivots = currPivots(spatFoc{:});
        else
            phi0s = 0;
            phi1s = 0;
            pivots = 1;
        end
        if isempty(phi0s)
            phi0s = 0;
        else
            phi0s = phi0s(1);
        end
        if isempty(phi1s)
            phi1s = 0;
        else
            phi1s = phi1s(1);
        end
        if isempty(pivots)
            pivots = 1;
        else
            pivots = pivots(1);
        end
        psObj.specData = prevData_foc;
        psObj.ppmAx = dataObj.xppm;
        psObj.phi0 = phi0s;
        psObj.phi1 = phi1s;
        psObj.pivot_ind = pivots;
    end
    if isempty(psObj.panel)
        psObj.initGraphics;
    end
    psObj.updateGraphics;st
    psObj.updatePlot("reframe",1);
end