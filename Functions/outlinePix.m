function outlinePix(ax,x,y,varargin)
    %Creates a box around location x,y with side lengths 1. 
    hold(ax,'on');
    plot(ax,[x-0.5,x-0.5,x+0.5,x+0.5,x-0.5], ...
                        [y+0.5,y-0.5,y-0.5,y+0.5,y+0.5],varargin{:})
    hold(ax,'off');
end