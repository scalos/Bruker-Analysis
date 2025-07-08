function p0 = natPol(T,B0,nuc)
	arguments
		T 
		B0
		nuc {mustBeMember(nuc,{'13C'})};
    end
    switch nuc
        case '13C'
		    gamma = 6.73e7; %rad/s/T
    end

	hbar = 1.05e-34; %Js
	kB = 1.38e-23; %J/T
	p0 = hbar*gamma*B0/(2*kB*T)*100;
end