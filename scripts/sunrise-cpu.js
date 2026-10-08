// Development-only Canvas reference renderer for cloud browsers without WebGL.
// The motion function below is generated from the current Metal Sunrise branch.
async function runCPUPreview(source) {
  const $ = id => document.getElementById(id), canvas = $('painting');
  const ctx = canvas.getContext('2d', {willReadFrequently: true});
  if (!ctx) throw Error('Canvas 2D unavailable');
  const smoothstep = (a,b,x) => {const t=Math.max(0,Math.min(1,(x-a)/(b-a)));return t*t*(3-2*t)};
  const motion = new Function('p','angle','m','strength','smoothstep', source.cpuMotion);
  async function load(path) {const im=new Image();im.src=path;await im.decode();const c=document.createElement('canvas');c.width=im.width;c.height=im.height;const cx=c.getContext('2d',{willReadFrequently:true});cx.drawImage(im,0,0);return {width:im.width,height:im.height,data:cx.getImageData(0,0,im.width,im.height).data}}
  const painting=await load('painting.jpg'), mask=await load('mask.png'), imageAspect=painting.width/painting.height;
  document.querySelector('.tag').textContent='Canvas CPU 云端参考渲染';
  document.querySelector('.note').textContent='当前云浏览器未提供 WebGL2，使用从 Metal 动效分支转译的 CPU 参考渲染。遮罩羽化为近似；此页不验证 Metal 编译、Mac 原生界面、导出或锁屏。';
  // Match normalized linear clamp-to-edge sampling, including pixel-center offsets.
  function sample(image,x,y,out) {
    const px=Math.max(0,Math.min(image.width-1,x*image.width-.5)),py=Math.max(0,Math.min(image.height-1,y*image.height-.5));
    const x0=Math.floor(px),y0=Math.floor(py),x1=Math.min(x0+1,image.width-1),y1=Math.min(y0+1,image.height-1),fx=px-x0,fy=py-y0,d=image.data;
    const a=(y0*image.width+x0)*4,b=(y0*image.width+x1)*4,c=(y1*image.width+x0)*4,e=(y1*image.width+x1)*4;
    for(let k=0;k<3;k++)out[k]=(d[a+k]*(1-fx)+d[b+k]*fx)*(1-fy)+(d[c+k]*(1-fx)+d[e+k]*fx)*fy;
  }
  let phase=8,paused=false,last=performance.now(),lastPaint=0, geometry=[];
  function resize(){canvas.width=960;canvas.height=$('ratio').value==='wide'?600:$('ratio').value==='ultrawide'?540:Math.round(960/imageAspect);const aspect=canvas.width/canvas.height;geometry=[];const color=new Float64Array(3),mcolor=new Float64Array(3);for(let y=0;y<canvas.height;y++)for(let x=0;x<canvas.width;x++){let px=(x+.5)/canvas.width,py=(y+.5)/canvas.height;if(aspect>imageAspect)py=(py-.5)*imageAspect/aspect+.5;else px=(px-.5)*aspect/imageAspect+.5;sample(painting,px,py,color);sample(mask,px,py,mcolor);const edge=smoothstep(0,.02,Math.min(px,1-px,py,1-py));geometry.push({p:{x:px,y:py},m:smoothstep(.04,.96,mcolor[0]/255)*edge,color:[...color]})}}
  function pixels(time,strength,showMask=false) {
    const frame=ctx.createImageData(canvas.width,canvas.height),data=frame.data,angle=((time/24)%1)*2*Math.PI,sampled=new Float64Array(3);
    for(let j=0;j<geometry.length;j++){const {p,m,color}=geometry[j],i=j*4;if(showMask){data[i]=color[0]*(1-m*.65)+.23*255*m*.65;data[i+1]=color[1]*(1-m*.65)+.80*255*m*.65;data[i+2]=color[2]*(1-m*.65)+.96*255*m*.65}else if(m<.001||strength===0){for(let c=0;c<3;c++)data[i+c]=color[c]}else{const result=motion(p,angle,m,strength,smoothstep);sample(painting,Math.max(0,Math.min(1,p.x+result.offset.x*strength*m)),Math.max(0,Math.min(1,p.y+result.offset.y*strength*m)),sampled);for(let c=0;c<3;c++)data[i+c]=(color[c]*(1-m)+sampled[c]*m)*result.light}data[i+3]=255}return frame;
  }
  function render(){ctx.putImageData(pixels(phase,+$('strength').value,$('showMask').checked),0,0)}
  function verify(){const lines=[];try{const zero=pixels(0,0).data,first=pixels(0,1.4).data,middle=pixels(8,1.4).data,loop=pixels(24,1.4).data;let mismatch=0,changed=0;for(let i=0;i<first.length;i+=4){if(first[i]!==loop[i]||first[i+1]!==loop[i+1]||first[i+2]!==loop[i+2])mismatch++;if(Math.max(Math.abs(first[i]-middle[i]),Math.abs(first[i+1]-middle[i+1]),Math.abs(first[i+2]-middle[i+2]))>2)changed++}if(mismatch)throw Error(`loop: ${mismatch} differing pixels`);lines.push('PASS · CPU 参考帧 0s / 24s 完全一致');let checked=0;for(const[sx,sy]of source.anchors){const aspect=canvas.width/canvas.height,x=aspect>imageAspect?sx:(sx-.5)*imageAspect/aspect+.5,y=aspect>imageAspect?(sy-.5)*aspect/imageAspect+.5:sy;if(x<0||x>=1||y<0||y>=1)continue;const i=(Math.floor(y*canvas.height)*canvas.width+Math.floor(x*canvas.width))*4;for(let c=0;c<3;c++)if(first[i+c]!==zero[i+c]||first[i+c]!==middle[i+c])throw Error(`protected anchor moved: ${sx}, ${sy}`);checked++}lines.push(`PASS · ${checked} 处主体采样保持静止`);if(changed<=200)throw Error('insufficient local motion');lines.push(`PASS · ${changed.toLocaleString()} 像素检测到局部动效`);lines.push('未执行 · Metal / WebGL 着色器编译');$('report').className=''}catch(e){lines.push('FAIL · '+e.message);$('report').className='error'}$('report').textContent=lines.join('\n');render()}
  $('verify').onclick=verify;$('pause').onclick=()=>{paused=!paused;$('pause').textContent=paused?'继续播放':'暂停播放'};$('ratio').onchange=()=>{resize();render();$('report').textContent=''};$('speed').oninput=()=>{$('speedValue').value=(+$('speed').value).toFixed(2)+'×'};$('strength').oninput=()=>{$('strengthValue').value=Math.round(+$('strength').value*100)+'%';render()};$('showMask').onchange=render;
  resize();verify();
  function tick(now){if(!paused)phase=(phase+Math.min((now-last)/1000,.2)*+$('speed').value)%24;last=now;if(now-lastPaint>120){render();lastPaint=now;$('frame').textContent=(paused?'已暂停':'CPU 实时参考渲染')+' · '+phase.toFixed(2)+' s'}requestAnimationFrame(tick)}requestAnimationFrame(tick);
}
