function newData = K_R_Tform(data,tFormMat,invert)
    arguments
        data 
        tFormMat 
        invert {mustBeNumericOrLogical} = false;
    end
    newData = data;
    nDims = length(size(data));
    for dim = (1:nDims)
        if size(data,dim)>1
            tForms = tFormMat{dim};
            for ind = (length(tForms):-1:1)
                tForm = lower(tForms{ind});
                switch tForm
                    case 'fftshift'
                        if invert
                            newData = ifftshift(newData,dim);
                        else
                            newData = fftshift(newData,dim);
                        end
                    case 'fft'
                        if invert
                            newData = ifft(newData,[],dim);
                        else
                            newData = fft(newData,[],dim);
                        end
                    case 'ifftshift'
                        if invert
                            newData = fftshift(newData,dim);
                        else
                            newData = ifftshift(newData,dim);
                        end
                    case 'ifft'
                        if invert
                            newData = fft(newData,[],dim);
                        else
                            newData = ifft(newData,[],dim);
                        end
                    otherwise
                        error('Excepted tForm types are: ''fftshift'',''fft'',''ifftshift'',''ifft''');
                end
            end
        end
    end
end

