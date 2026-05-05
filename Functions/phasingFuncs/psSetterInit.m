function psSetterInit(setter)
    %Initializes phasing window
    assert(isa(setter,'ProcSetter'));
    psObj = PhaseAdj([]);
    psObj.applyPhaseFun = @(~,~) setter.apply();
    setter.viewerObj = psObj;
    
    setter.update;
end