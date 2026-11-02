/* Botón de info para el Cierre nocturno: explica qué es cada dato.
   Para cambiar un texto, editá la lista INFO de abajo. No toca ninguna cuenta. */
(function(){
 var INFO=[
  ['1) Surtidores',[
   ['Inicio / Cierre','Lectura del contador de cada surtidor (S1 a S4) al empezar y al terminar. La diferencia, cierre − inicio, es lo que vendió ese surtidor.'],
   ['Venta Tanque 1 / 2','Tanque 1 = S1 + S2. Tanque 2 = S3 + S4. Es la suma de lo vendido por sus dos surtidores.']]],
  ['2) Telemedición',[
   ['Sondas','Sondas 1 y 2 miden el Tanque 1. Sondas 3 y 4 miden el Tanque 2. Cada tanque se mide sumando sus dos sondas.'],
   ['Inicio (opcional)','Lectura de las sondas al empezar. Solo sirve para calcular el consumo por telemedición.'],
   ['Final / Medición final (E)','Lectura de las sondas al cerrar, ahora. La medición final de un tanque es la suma de sus dos sondas.'],
   ['Consumo telemedición','Lo que bajó el tanque según las sondas: inicio + ingresos − final.']]],
  ['3) Planilla',[
   ['A · Stock inicial','Stock de combustible resultado del cierre de la noche anterior. Se completa solo con la medición final que guardaste ayer; si hace falta, lo podés corregir.'],
   ['B · Ingresos','Litros que entraron por camión durante el período. Solo se carga si tildás "Entró camión hoy".'],
   ['C · Consumos','Lo vendido por los surtidores de ese tanque (la Venta de arriba).'],
   ['D · Stock esperado','D = A + B − C. Lo que debería haber en el tanque según lo que entró y lo que se vendió.'],
   ['E · Medición final','Lo que realmente marcan las sondas ahora (telemedición).'],
   ['E − D · Diferencia','Lo medido menos lo esperado. Si pasa de 150 L (en más o en menos) se pone en rojo: puede ser un surtidor trabado, un error de lectura o una pérdida.']]],
  ['Botones',[
   ['Guardar cierre','La medición final (E) queda guardada y mañana se carga sola como stock inicial (A).'],
   ['Nuevo cierre','Borra todo lo cargado para empezar uno nuevo. El stock inicial se vuelve a tomar del último cierre guardado.']]]
 ];
 function esc(s){return String(s).replace(/[&<>]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;'}[c]})}
 var css=document.createElement('style');
 css.textContent='.ib{display:block;margin:18px auto 4px;width:30px;height:30px;padding:0;border-radius:50%;flex:none;font-size:.85rem;font-weight:700;color:var(--muted,#8b95a1);background:transparent;border:1px solid var(--line,#2a323b)}'+
 '.ibl{text-align:center;font-size:.66rem;color:var(--muted,#8b95a1);margin:0 0 8px}'+
 '.iov{position:fixed;inset:0;z-index:50;background:rgba(0,0,0,.6);display:none;align-items:flex-end;justify-content:center}'+
 '.iov.on{display:flex}'+
 '.isheet{width:100%;max-width:520px;max-height:86vh;overflow:auto;background:var(--panel,#1a2027);border:1px solid var(--line,#2a323b);border-radius:14px 14px 0 0;padding:16px 16px calc(18px + env(safe-area-inset-bottom,0px))}'+
 '.isheet h3{font-size:1rem;margin:0 0 4px}.isheet h4{font-size:.74rem;text-transform:uppercase;letter-spacing:.08em;color:var(--diesel,#d9a441);margin:16px 0 6px}'+
 '.isheet dt{font-weight:700;font-size:.88rem;margin-top:8px}.isheet dd{margin:2px 0 0;font-size:.84rem;line-height:1.45;color:var(--muted,#8b95a1)}'+
 '.isheet .x{display:block;width:100%;margin-top:16px}';
 document.head.appendChild(css);
 var body='<h3>¿Qué es cada dato?</h3>'+INFO.map(function(g){return '<h4>'+esc(g[0])+'</h4><dl style="margin:0">'+g[1].map(function(r){return '<dt>'+esc(r[0])+'</dt><dd>'+esc(r[1])+'</dd>'}).join('')+'</dl>'}).join('')+'<button class="x" id="ix">Cerrar</button>';
 var ov=document.createElement('div');ov.className='iov';ov.innerHTML='<div class="isheet" role="dialog" aria-label="Información">'+body+'</div>';
 document.body.appendChild(ov);
 var b=document.createElement('button');b.className='ib';b.id='ib';b.setAttribute('aria-label','Información sobre cada dato');b.textContent='i';
 var l=document.createElement('p');l.className='ibl';l.textContent='Info';
 var w=document.querySelector('.wrap')||document.body;w.appendChild(b);w.appendChild(l);
 function open(){ov.classList.add('on')}function close(){ov.classList.remove('on')}
 b.onclick=open;ov.onclick=function(e){if(e.target===ov||e.target.id==='ix')close()};
 /* el botón/gesto "atrás" del celular cierra la info antes de salir de la herramienta */
 window.__back=function(){if(ov.classList.contains('on')){close();return true}return false};
})();
