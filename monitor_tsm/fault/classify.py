"""Outcome rules and dependency-free exact binomial intervals."""
import argparse, collections, json, math, re
from pathlib import Path
HERE=Path(__file__).resolve().parent
FIELDS=['RSP','CMD','EVENT','ING','SUP','LOST','REASON','STATUS']

def parse(text):
    matches=re.findall(r'^RESULT (.*)$',text,re.M)
    if len(matches)!=1: return dict(error='missing/duplicate RESULT')
    result={k:int(v,16 if k=='fallback' else 10) for k,v in re.findall(r'(\w+)=(\w+)',matches[0])}
    result['pairs']={}
    for key in FIELDS:
        m=re.search(r'^'+key+r' (\w+) (\w+)$',text,re.M)
        if not m or re.search('[xz]',m[1]+m[2],re.I):
            return dict(error='missing/unknown '+key,raw=result)
        result['pairs'][key]=[int(m[1],16),int(m[2],16)]
    return result

def classify(obs,baseline=None,reference=False):
    if 'error' in obs: return 'UNRESOLVED'
    if not reference and (not obs['injected'] or not obs['probe']): return 'UNRESOLVED'
    p=obs['pairs']; rsp,gold=p['RSP']; cmd,gcmd=p['CMD']
    accept=bool(rsp>>37)
    # Any changed accepted command is conservatively uncertified. Also recognize
    # command authority (modes L0/L1) even if response ACCEPT was corrupted low.
    cmd_authority=obs['frames']>0 and cmd>>1894<=1
    g_authority=gcmd>>1894<=1
    if (accept and (not gold>>37 or cmd!=gcmd or (rsp^gold)&(((1<<26)-1)^((1<<10)-1)))) or (cmd_authority and (not g_authority or cmd!=gcmd)):
        return 'SDC-UNSAFE'
    if obs['hang']: return 'DETECTED' if obs['deadline'] else 'HANG'
    equal=all(a==b for a,b in p.values()) and obs['frames']==1 and obs['event']==1 and not obs['framing']
    if equal: return 'MASKED'
    if reference: return 'UNRESOLVED'
    old=baseline['pairs']
    new_fault=bool(p['SUP'][0]&4) and not bool(old['SUP'][0]&4)
    health_bad=not bool(rsp&1) and bool(old['RSP'][0]&1)
    safe_reject=not accept and bool(gold>>37)
    fallback=obs['fallback']!=baseline['fallback'] and bool(obs['fallback'])
    if obs['deadline'] or new_fault or health_bad or safe_reject or fallback: return 'DETECTED'
    return 'SDC-SAFE'

def binom_cdf(k,n,p):
    if p==0:return 1.0
    if p==1:return float(k==n)
    terms=[math.lgamma(n+1)-math.lgamma(i+1)-math.lgamma(n-i+1)+i*math.log(p)+(n-i)*math.log1p(-p) for i in range(k+1)]
    m=max(terms)
    return min(1.0,math.exp(m)*sum(math.exp(t-m) for t in terms))

def cp(k,n):
    if not n:return None
    def solve(j,target):
        lo,hi=0.,1.
        for _ in range(70):
            mid=(lo+hi)/2
            if binom_cdf(j,n,mid)>target:lo=mid
            else:hi=mid
        return (lo+hi)/2
    return [0. if k==0 else solve(k-1,.975),1. if k==n else solve(k,.025)]

def summary(rows):
    counts=collections.Counter(r['class'] for r in rows)
    eligible=sum(counts[c] for c in ['MASKED','DETECTED','SDC-SAFE','SDC-UNSAFE','HANG'])
    dcden=sum(counts[c] for c in ['DETECTED','SDC-SAFE','SDC-UNSAFE'])
    return dict(attempts=len(rows),counts=dict(counts),n=eligible,unsafe_rate=counts['SDC-UNSAFE']/eligible if eligible else None,cp95=cp(counts['SDC-UNSAFE'],eligible),dc=counts['DETECTED']/dcden if dcden else None)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('results',nargs='?',default=str(HERE/'results.jsonl'));a=ap.parse_args()
    rows=[json.loads(s) for s in Path(a.results).read_text().splitlines() if s.strip()]
    out=dict(overall=summary(rows),units={u:summary([r for r in rows if r['unit']==u]) for u in sorted({r['unit'] for r in rows})},unsafe=[r for r in rows if r['class']=='SDC-UNSAFE'])
    path=Path(a.results).with_suffix('.summary.json');path.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))

if __name__=='__main__':main()
