# Bulletins d'or — calcul indépendant du moteur SQL, à partir des seules sources (septembre 2026)
from decimal import Decimal as D, ROUND_HALF_UP
def r2(x): return D(x).quantize(D('0.01'), ROUND_HALF_UP)
def r4(x): return D(x).quantize(D('0.0001'), ROUND_HALF_UP)
PMSS=D('4005'); SMIC_M=D('1867.02'); ATMP=D('1.00')  # AT/MP : taux notifié hypothétique du jeu d'essai
PAS=[(0,1635,0),(1635,1698,0.5),(1698,1807,1.3),(1807,1928,2.1),(1928,2060,2.9),(2060,2170,3.5),(2170,2315,4.1),(2315,2738,5.3),(2738,3135,7.5),(3135,3571,9.9),(3571,4019,11.9),(4019,4690,13.8),(4690,5624,15.8),(5624,7037,17.9),(7037,8789,20),(8789,12200,24),(12200,16523,28),(16523,25937,33),(25937,55558,38),(55558,None,43)]
def slip(g, cadre=False):
    g=D(g); T1=min(g,PMSS); T2=max(D(0),min(g,8*PMSS)-PMSS); T12=min(g,8*PMSS)
    lines=[ # (label, base, sal%, pat%, RGDU-eligible)
     ('maladie', g, 0, 13, 1), ('vieil_plaf', T1, D('6.90'), D('8.55'), 1), ('vieil_deplaf', g, D('0.40'), D('2.11'), 1),
     ('af', g, 0, D('5.25'), 1), ('csa', g, 0, D('0.30'), 1), ('atmp', g, 0, ATMP, 1), ('fnal', T1, 0, D('0.10'), 1),
     ('dialogue', g, 0, D('0.016'), 0), ('chomage', min(g,4*PMSS), 0, D('4.00'), 1), ('ags', min(g,4*PMSS), 0, D('0.25'), 0),
     ('aa_t1', T1, D('3.15'), D('4.72'), 1), ('ceg_t1', T1, D('0.86'), D('1.29'), 1),
     ('aa_t2', T2, D('8.64'), D('12.95'), 0), ('ceg_t2', T2, D('1.08'), D('1.62'), 0)]
    if g > PMSS: lines.append(('cet', T12, D('0.14'), D('0.21'), 0))
    if cadre: lines.append(('apec', min(g,4*PMSS), D('0.024'), D('0.036'), 0))
    sal=pat=elig=D(0); det={}
    for (l,b,s,p,e) in lines:
        a_s=r2(b*D(s)/100); a_p=r2(b*D(p)/100); sal+=a_s; pat+=a_p; elig+= a_p if e else 0; det[l]=(a_s,a_p)
    csgb=r2(min(g,4*PMSS)*D('98.25')/100 + max(D(0),g-4*PMSS))
    csgd=r2(csgb*D('6.80')/100); csgn=r2(csgb*D('2.40')/100); crds=r2(csgb*D('0.50')/100)
    red=D(0); coef=D(0)
    if g < 3*SMIC_M:
        coef=min(D('0.3981'), r4(D('0.02')+D('0.3781')*(D('0.5')*(3*SMIC_M/g-1))**D('1.75')))
        red=min(r2(coef*g), elig)
    net_imp=r2(g-sal-csgd)
    rate=[p for (lo,hi,p) in PAS if net_imp>=lo and (hi is None or net_imp<hi)][0]
    pas=r2(net_imp*D(str(rate))/100)
    net=r2(g-sal-csgd-csgn-crds-pas)
    return dict(gross=g, sal=sal, pat=pat-red, red=red, coef=coef, csgb=csgb, csgd=csgd, csgn=csgn, crds=crds, net_imp=net_imp, pas_rate=rate, pas=pas, net=net)
for g,c in [('1867.02',False),('2500',False),('4500',True)]:
    print(g, 'cadre' if c else 'non cadre', {k:str(v) for k,v in slip(g,c).items()})
