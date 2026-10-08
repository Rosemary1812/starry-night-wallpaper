#!/usr/bin/env python3
"""Generate development-only cloud previews from native artwork source.

No app UI is simulated: these pages run the same movement arithmetic on the CPU
when WebGL2 is unavailable. Core Image mask feather remains an approximation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
FLOAT = r'[-+]?(?:\d+\.?\d*|\.\d+)'

def block_after(source, marker):
    start = source.index(marker) + len(marker)
    depth = 1
    for index in range(start, len(source)):
        if source[index] == '{': depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0: return source[start:index]
    raise ValueError('Unterminated native block: ' + marker)

def native_catalog():
    text = (ROOT / 'Artwork.swift').read_text()
    cases = []
    for line in text.split('// The Met reproduction')[0].splitlines():
        if line.strip().startswith('case '): cases.extend(line.strip()[5:].split(', '))
    def strings(name):
        body = block_after(text, 'var ' + name + ': String {')
        return re.findall(r'"([^"\n]*)"', body)
    names, years = [strings(n) for n in ['filename', 'year']]
    if 'L10n.tr' in text:
        resources = dict(re.findall(r'^"([^"]+)"\s*=\s*"([^"]*)";',
            (ROOT / 'zh-Hans.lproj/Localizable.strings').read_text(), re.M))
        titles = [resources['artwork.' + name + '.name'] for name in names]
        descriptions = [resources['artwork.' + name + '.description'] for name in names]
    else:
        titles, descriptions = [strings(n) for n in ['title', 'description']]
    assert len(cases) == len(names) == len(titles) == len(years) == len(descriptions)
    bounds = {case: [float(v) for v in values] for case,*values in re.findall(
        r'case \.(\w+): return CGRect\(x:\s*('+FLOAT+r'), y:\s*('+FLOAT+r'), width:\s*('+FLOAT+r'), height:\s*('+FLOAT+r')\)', text)}
    artists = {'starryNight':'文森特·梵高','rhone':'文森特·梵高','cypresses':'文森特·梵高',
        'nocturneBognor':'詹姆斯·麦克尼尔·惠斯勒','approachVenice':'约瑟夫·马洛德·威廉·特纳','bridgeVilleneuve':'阿尔弗雷德·西斯莱'}
    return {name:dict(id=i,case=case,name=title.split(' · ')[-1],title=title,year=year,
        artist=artists.get(case,'克劳德·莫奈'),description=description,bounds=bounds.get(case,[0,0,1,1]))
        for i,(case,name,title,year,description) in enumerate(zip(cases,names,titles,years,descriptions))}

def make_mask(swift,case,bounds):
    body = block_after(swift,'if artwork == .'+case+' {')
    polygons = []
    for raw in re.findall(r'protect\(\[(.*?)\]\)', body, re.S):
        polygons.append([tuple(map(float,p)) for p in re.findall(r'\(('+FLOAT+r'),\s*('+FLOAT+r')\)', raw)])
    assert polygons or 'fillEllipse' in body, 'No recognized protection geometry for '+case
    mask=Image.new('L',(2048,1622),255); draw=ImageDraw.Draw(mask)
    for polygon in polygons: draw.polygon([(x*2048,y*1622) for x,y in polygon],fill=0)
    for array in re.findall(r'for \(x,y,rx,ry\) in \[(.*?)\]',body,re.S):
        for coords in re.findall(r'\(('+FLOAT+r'),\s*('+FLOAT+r'),\s*('+FLOAT+r'),\s*('+FLOAT+r')\)',array):
            x,y,rx,ry=map(float,coords);draw.ellipse(((x-rx)*2048,(y-ry)*1622,(x+rx)*2048,(y+ry)*1622),fill=0)
    mask=mask.filter(ImageFilter.MinFilter(17)).filter(ImageFilter.GaussianBlur(4))
    x,y,w,h=bounds
    return mask.crop((round(x*2048),round(y*1622),round((x+w)*2048),round((y+h)*1622)))

def generate(output,artwork):
    source=(ROOT/'Sky.metal').read_text();swift=(ROOT/'StarryNight.swift').read_text()
    meta=native_catalog()[artwork];bounds=meta['bounds'];case=meta['case']
    output.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ROOT/'THIRD-PARTY-NOTICES.md',output/'THIRD-PARTY-NOTICES.md')
    make_mask(swift,case,bounds).save(output/'mask.png')
    assets=Path(os.environ.get('STARRY_ASSETS_DIR',ROOT/'assets'))
    with Image.open(assets/(artwork+'.jpg')) as im:
        x,y,w,h=bounds;im=im.crop((round(x*im.width),round(y*im.height),round((x+w)*im.width),round((y+h)*im.height)))
        im.thumbnail((2560,2560),Image.Resampling.LANCZOS);im.save(output/'painting.jpg',quality=96)
    anchors_text=swift.split('case .'+case+': anchors = [',1)[1].split(']',1)[0]
    raw_anchors=[tuple(map(float,p)) for p in re.findall(r'\(('+FLOAT+r'),\s*('+FLOAT+r')\)',anchors_text)]
    x,y,w,h=bounds;anchors=[((px-x)/w,(py-y)/h) for px,py in raw_anchors]
    body=source.split('// BEGIN motion: '+artwork,1)[1].split('// END motion: '+artwork,1)[0]
    cpu=re.sub(r'//[^\n]*','',body).replace('float2(','vec2(')
    cpu=re.sub(r'\bfloat ','let ',cpu).replace('u.strength','strength')
    for fn in ['sin','cos','exp','abs','min','max','sqrt']:
        cpu=re.sub(r'\b'+fn+r'\(','Math.'+fn+'(',cpu)
    cpu='let offset={x:0,y:0},light=1; const vec2=(x,y)=>({x,y}); const mix=(a,b,t)=>a*(1-t)+b*t;\n'+cpu+'\nreturn {offset,light};'
    def glsl(text):
        text=re.sub(r'constexpr sampler s\([^;]+;','',text)
        text=text.replace('texture2d<float>','sampler2D')
        text=re.sub(r'\bfloat([234])\b',r'vec\1',text)
        text=re.sub(r'(painting|mask)\.sample\(s,',r'texture(\1,',text)
        return text.replace('M_PI_F','3.14159265358979323846').replace('in.uv','vUV')
    functions=glsl(source[source.index('float2 vortex('):source.index('fragment float4 fragmentMain')])
    fragment=glsl(source.split('constant Parameters &u [[buffer(0)]]) {',1)[1])
    fragment=re.sub(r'return ([^;]+);',r'{ fragColor = \1; return; }',fragment)
    shader='''#version 300 es
precision highp float;
uniform sampler2D painting;
uniform sampler2D mask;
struct Parameters { float time; float strength; float aspect; float showMask; float artwork; float imageAspect; };
uniform Parameters u;
in vec2 vUV;
out vec4 fragColor;
'''+functions+'\nvoid main() {'+fragment
    data={'cpuMotion':cpu,'fragment':shader,'anchors':anchors,'sourceSHA256':hashlib.sha256(source.encode()).hexdigest(),'meta':meta}
    (output/'source-data.js').write_text('const SOURCE = '+json.dumps(data,ensure_ascii=False)+';\n')
    for name in ['sunrise-cpu.js','sunrise-preview.html']:
        shutil.copyfile(ROOT/'scripts'/name,output/('index.html' if name.endswith('.html') else name))
    print('Generated',artwork,output)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artwork',default='impression-sunrise',choices=[slug for slug,meta in native_catalog().items() if meta['id']>=5])
    parser.add_argument('--output',type=Path,default=None)
    args=parser.parse_args();generate(args.output or ROOT/'dist/artwork-previews'/args.artwork,args.artwork)
