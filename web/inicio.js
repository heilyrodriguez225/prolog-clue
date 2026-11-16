const nombre = document.getElementById('nombre');
const contador = document.getElementById('contador');
nombre.addEventListener('input', () => {
  contador.textContent = `${nombre.value.length}/20`;
});

function exclusivo(contenedorId, clase) {
  const botones = document.querySelectorAll(`#${contenedorId} ${clase}`);
  botones.forEach(b => b.addEventListener('click', () => {
    botones.forEach(x => x.classList.remove('sel'));
    b.classList.add('sel');
  }));
}
exclusivo('rivales', '.op-rival');
// La demo necesita la libreta: encenderla y no dejar apagarla.
document.getElementById('espectador').addEventListener('change', (ev) => {
  const a = document.getElementById('asistente');
  if (ev.target.checked) a.checked = true;
  a.disabled = ev.target.checked;
});

// Un nivel por rival. La API usa facil, media y dificil; la página dice Fácil, Medio y Difícil.
const NIVELES = [
  { api: 'facil', texto: 'Fácil', desc: 'Sugiere lo que no ha visto y acusa cuando le queda una carta de cada tipo' },
  { api: 'media', texto: 'Medio', desc: 'Deduce con restricciones todo lo que ve en la mesa' },
  { api: 'dificil', texto: 'Difícil', desc: 'Pregunta lo que más reduce su incertidumbre' },
];
let nombresIA = ['Beto', 'Cleo', 'Dani', 'Elena'];
// Por defecto: una media y las demás fáciles.
const elegidos = ['media', 'facil', 'facil', 'facil'];

fetch('/api/config').then((r) => r.json()).then((c) => { nombresIA = c.nombres; pintarNiveles(); }).catch(() => {});

function cuantosRivales() {
  return Number(document.querySelector('#rivales .sel').dataset.valor);
}

function pintarNiveles() {
  const cont = document.getElementById('niveles-rivales');
  cont.innerHTML = '';
  for (let i = 0; i < cuantosRivales(); i++) {
    const fila = document.createElement('div');
    fila.className = 'fila-nivel';
    const etiqueta = document.createElement('span');
    etiqueta.className = 'rival-nombre';
    etiqueta.textContent = nombresIA[i] + ' (IA)';
    fila.append(etiqueta);
    const grupo = document.createElement('div');
    grupo.className = 'grupo-nivel';
    for (const n of NIVELES) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'op-nivel' + (elegidos[i] === n.api ? ' sel' : '');
      b.textContent = n.texto;
      b.title = n.desc;
      b.addEventListener('click', () => { elegidos[i] = n.api; pintarNiveles(); });
      grupo.append(b);
    }
    fila.append(grupo);
    cont.append(fila);
  }
  const dificiles = elegidos.slice(0, cuantosRivales()).filter((x) => x === 'dificil').length;
  document.getElementById('ayuda-niveles').textContent = dificiles
    ? '👁 La IA difícil piensa un poco más en cada turno'
    : '👁 Elige el nivel de cada rival: se ve en su asiento';
}

document.querySelectorAll('#rivales .op-rival').forEach((b) => b.addEventListener('click', pintarNiveles));
pintarNiveles();

document.getElementById('entrar').addEventListener('click', async (ev) => {
  ev.preventDefault();
  const espectador = document.getElementById('espectador').checked;
  const rivales = elegidos.slice(0, cuantosRivales()).map((nivel) => ({ nivel }));
  const cuerpo = {
    nombre: nombre.value,
    asistente: espectador || document.getElementById('asistente').checked,
    modo: espectador ? 'espectador' : 'jugar',
    rivales,
  };
  try {
    const r = await fetch('/api/partida', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo),
    });
    const datos = await r.json();
    if (!r.ok) throw new Error(datos.mensaje || 'Error');
    location.href = `index.html#${datos.id}`;
  } catch (e) {
    alert('No se pudo crear la partida: ' + e.message);
  }
});

const reglas = document.getElementById('reglas');
document.getElementById('como-jugar').addEventListener('click', () => reglas.showModal());
document.getElementById('cerrar-reglas').addEventListener('click', () => reglas.close());
