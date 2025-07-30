function score = symScore(data,pkInd,pkWidth)
    arguments
        data (:,1) %real spectral data
        pkInd
        pkWidth        
    end
    if data(pkInd)<mean(data)
        score = 1;
        return
    end
    pkWidth = round(pkWidth);
    leftSide = data(max(1,pkInd-pkWidth):pkInd-1);
    rightSide = data(pkInd:min(length(data),pkInd+pkWidth));
    minSize = min(size(leftSide),size(rightSide));
    rightSide = rightSide(1:minSize(1));
    leftSide = leftSide(end-minSize(1)+1:end);
    leftFlipped = flip(leftSide);
    wholeInt = abs(trapz(leftFlipped))+abs(trapz(rightSide));
    if wholeInt == 0
        score = 1;
        return
    end
    score = abs(trapz(leftFlipped-rightSide))/wholeInt;
end