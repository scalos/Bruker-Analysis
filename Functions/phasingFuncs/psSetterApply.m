function psSetterApply(setter)
    assert(isa(setter,'ProcSetter'));
    psObj = setter.viewerObj;
    psObj.applyPhaseButton.Enable = 'off';
    procStep = setter.procStep;
    dataObj = setter.dataObj;
    prevData = dataObj.getProcStepInput(procStep);
    phi0 = psObj.phi0;
    phi1 = psObj.phi1;
    pivot = psObj.pivot_ind;
    if isempty(procStep.params)
        procStep.params{1} = zeros(size(prevData,2:ndims(prevData)));
        procStep.params{2} = zeros(size(prevData,2:ndims(prevData)));
        procStep.params{3} = zeros(size(prevData,2:ndims(prevData)));
    end
    newPhi0 = procStep.params{1};
    newPhi1 = procStep.params{2};
    newPivot = procStep.params{3};
    spatFoc_ = dataObj.rFocus(2:end);
    if ~procStep.constInRegion(spatFoc_)
        res = uiconfirm(ancestor(psObj.panel,'figure'),'WARNING: the current focus spans more than one unique phase. Override phases in this region?','Phase Conflict');
        switch res
            case 'OK'
                newPhi0 = repmat(phi0,size(newPhi0));
                newPhi1 = repmat(phi1,size(newPhi1));
                newPivot = repmat(pivot,size(newPivot));
            case 'Cancel'
                psObj.applyPhaseButton.Enable = 'on';
                return;
        end
    end

    newPhi0(spatFoc_{:}) = phi0;
    newPhi1(spatFoc_{:}) = phi1;
    newPivot(spatFoc_{:}) = pivot;
    procStep.setParams({newPhi0,newPhi1,newPivot})
    dataObj.updateProc;
    psObj.applyPhaseButton.Enable = 'on';
end