figure;

recon.prefs.colorBar.tickLoc = 'right';
recon.dispAx = subplot('Position',[0.03,0.5,0.2,0.5]);
recon.setVis(0);
recon.prefs.colorBar.visible = false;
recon.show;
axis(recon.dispAx,[77.1301 138.3072 53.0110 114.1881]);
recon.prefs.colorBar.visible = true;
ax = recon.dispAx;

for idx = 2:4
    recon.dispAx = subplot('Position',[0.25*(idx-1),0.5,0.2,0.5]);
    recon.cbAx = subplot('Position',[0.25*(idx-1)+0.205,0.53,0.01,0.44]);
    recon.setVis(idx-1);
    recon.prefs.colorBar.targInd = idx-1;
    recon.show;
    axis(recon.dispAx,[77.1301 138.3072 53.0110 114.1881]);
end


recon_o.dispAx = subplot('Position',[0.03,0,0.2,0.5]);
recon_o.prefs.colorBar.tickLoc = 'right';
recon_o.setVis(0);
recon_o.prefs.colorBar.visible = false;
recon_o.show;
axis(recon_o.dispAx,[58.9001 132.9244 76.2474 150.2717]);
recon_o.prefs.colorBar.visible = true;

for idx = 2:4
    recon_o.dispAx = subplot('Position',[0.25*(idx-1),0,0.2,0.5]);
    recon_o.cbAx = subplot('Position',[0.25*(idx-1)+0.205,0.03,0.01,0.44]);
    recon_o.setVis(idx-1);
    recon_o.prefs.colorBar.targInd = idx-1;
    recon_o.show;
    axis(recon_o.dispAx,[58.9001 132.9244 76.2474 150.2717]);
end