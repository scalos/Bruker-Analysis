function tf = psSetterIsActive(setter)
    psObj = setter.viewerObj;
    if isempty(psObj)
        tf = false;
        return;
    end
    p = psObj.panel;
    tf = false;
    if isvalid(p)
        tf = true;
    end
end