// Maqueta estática: los datos son de ejemplo. Más adelante vendrán de la API (servidor.pl).

const CARTAS = [
  ['sospechoso', 'chef_canela', 'Chef Canela'],
  ['sospechoso', 'entrenador_cobalto', 'Entrenador Cobalto'],
  ['sospechoso', 'senora_coral', 'Señora Coral'],
  ['sospechoso', 'jardinero_verde', 'Jardinero Verde'],
  ['sospechoso', 'doctora_violeta', 'Doctora Violeta'],
  ['sospechoso', 'senorita_perla', 'Señorita Perla'],
  ['arma', 'trofeo', 'Trofeo'],
  ['arma', 'veneno', 'Veneno'],
  ['arma', 'cuerda', 'Cuerda'],
  ['arma', 'daga', 'Daga'],
  ['arma', 'revolver', 'Revólver'],
  ['arma', 'tijeras', 'Tijeras'],
  ['lugar', 'biblioteca', 'Biblioteca'],
  ['lugar', 'cocina', 'Cocina'],
  ['lugar', 'sala_de_video', 'Sala de video'],
  ['lugar', 'piscina', 'Piscina'],
  ['lugar', 'comedor', 'Comedor'],
  ['lugar', 'estudio', 'Estudio'],
  ['lugar', 'bodega', 'Bodega'],
  ['lugar', 'gimnasio', 'Gimnasio'],
  ['lugar', 'jardin', 'Jardín'],
].map(([tipo, id, nombre]) => ({ tipo, id, nombre }));

const TIPOS = { sospechoso: 'Sospechoso', arma: 'Arma', lugar: 'Lugar' };
const TIPOS_PL = { sospechoso: 'Sospechosos', arma: 'Armas', lugar: 'Lugares' };
const ASIENTOS = ['norte', 'oeste', 'este', 'sur'];
const PALETA_IA = ['var(--vino)', 'var(--arma)', 'var(--lugar)', 'var(--morado)'];

// Jugador 0 es "Tú" (no se sienta en la mesa, se ve desde su silla).
const JUGADORES = [
  { nombre: 'Tú', cartas: 5 },
  { nombre: 'Ana', nivel: 'Medio', cartas: 5, activo: true },
  { nombre: 'Beto', nivel: 'Fácil', cartas: 4 },
  { nombre: 'Cleo', nivel: 'Difícil', cartas: 4, eliminado: true },
];

const MANO = ['doctora_violeta', 'daga', 'cocina', 'piscina', 'tijeras'];

const HISTORIAL = [
  { quien: 'Tú', texto: 'Chef Canela · Daga · Cocina', res: 'Beto refutó' },
  { quien: 'Ana', texto: 'Señora Coral · Veneno · Jardín', res: 'Nadie pudo refutar' },
  { quien: 'Beto', texto: 'Jardinero Verde · Cuerda · Estudio', res: 'Tú refutaste' },
];

// Estado de deducción por carta: 'descartado' (no está en el sobre),
// 'sospechoso' (podría estar), o sin entrada = sin pista todavía.
const ESTADOS = {
  doctora_violeta: 'descartado', daga: 'descartado', cocina: 'descartado',
  piscina: 'descartado', tijeras: 'descartado', chef_canela: 'descartado',
  veneno: 'sospechoso', jardin: 'sospechoso', senora_coral: 'sospechoso',
};

const el = (tag, clase, html) => {
  const e = document.createElement(tag);
  if (clase) e.className = clase;
  if (html !== undefined) e.innerHTML = html;
  return e;
};

function carta(c) {
  const e = el('article', `carta ${c.tipo}`);
  const enMano = MANO.includes(c.id);
  e.innerHTML = `
    <div class="rotulo">${TIPOS[c.tipo]}</div>
    <div class="arte">
      <span class="mono">${c.nombre[0]}</span>
      <img src="img/cartas/${c.id}.png" alt="" onerror="this.remove()">
    </div>
    <div class="pie">
      <span class="titulo">${c.nombre}</span>
      ${enMano ? '<span class="posesion">✓ En tu poder</span>' : ''}
    </div>`;
  return e;
}

function pintarMesa() {
  const ovalo = document.getElementById('mesa-ovalo');
  const ias = JUGADORES.slice(1);
  ias.forEach((j, i) => {
    const pos = ias.length === 2
      ? ['oeste', 'este'][i]
      : ASIENTOS[i];
    const e = el('div', `asiento ${pos}${j.activo ? ' activo' : ''}${j.eliminado ? ' eliminado' : ''}`);
    e.style.setProperty('--c', PALETA_IA[i % PALETA_IA.length]);
    e.innerHTML = `
      <div class="asiento-cab">
        <div class="avatar">${j.nombre[0]}</div>
        <div>
          <div class="nombre">${j.nombre} (IA)</div>
          <div class="rol">${j.nivel}</div>
        </div>
        <span class="cartas-n">${j.cartas} cartas</span>
      </div>
      <div class="estado">${j.eliminado ? 'Eliminado' : j.activo ? 'Pensando…' : 'En espera'}</div>`;
    ovalo.appendChild(e);
  });
}

function pintarEncabezado() {
  const activo = JUGADORES.find(j => j.activo) ?? JUGADORES[0];
  document.getElementById('turno-nombre').textContent = activo.nombre;
  document.getElementById('pildora-turno-nombre').textContent = activo.nombre;
}

function pintarSelectores() {
  const cont = document.getElementById('selectores');
  for (const tipo of Object.keys(TIPOS)) {
    const opciones = CARTAS.filter(c => c.tipo === tipo).map(c => `<option>${c.nombre}</option>`).join('');
    cont.append(el('div', 'slot', `<label>${TIPOS[tipo]}</label><select>${opciones}</select>`));
  }
}

function pintarHistorial() {
  const ultimo = HISTORIAL[HISTORIAL.length - 1];
  document.getElementById('actividad-ultimo').innerHTML =
    `<strong>${ultimo.quien}</strong> — ${ultimo.res.toLowerCase()}`;
  const ol = document.getElementById('historial');
  for (const h of [...HISTORIAL].reverse()) {
    ol.append(el('li', '', `<span class="quien">${h.quien}</span>: ${h.texto}<span class="res">${h.res}</span>`));
  }
}

function pintarLibreta(tipo) {
  document.getElementById('libreta-cab-titulo').textContent = TIPOS_PL[tipo];
  const cartasTipo = CARTAS.filter(c => c.tipo === tipo);
  document.getElementById('libreta-cab-total').textContent = `${cartasTipo.length} posibles`;

  const lista = document.getElementById('libreta-lista');
  lista.innerHTML = '';
  for (const c of cartasTipo) {
    const estado = ESTADOS[c.id] ?? 'sinpista';
    const icono = estado === 'descartado' ? '☒' : estado === 'sospechoso' ? '？' : '';
    lista.append(el('div', `fila-carta ${estado}`, `
      <span class="estado-ico">${icono}</span>
      <span class="nombre">${c.nombre}</span>`));
  }
}

function pintarProgreso() {
  const total = CARTAS.length - 3; // las 3 del sobre nunca se "descartan"
  const descartadas = Object.values(ESTADOS).filter(v => v === 'descartado').length;
  document.getElementById('progreso-txt').textContent = `${descartadas} de ${total} descartadas`;
  document.getElementById('progreso-rel').style.width = `${(descartadas / total) * 100}%`;
}

function pintarMano() {
  const cont = document.getElementById('mano');
  document.getElementById('mano-cuenta').textContent = `${MANO.length} cartas`;
  for (const id of MANO) cont.append(carta(CARTAS.find(c => c.id === id)));
}

function conectarTabs() {
  const tabs = document.querySelectorAll('.tab');
  tabs.forEach(t => t.addEventListener('click', () => {
    tabs.forEach(x => x.classList.remove('sel'));
    t.classList.add('sel');
    pintarLibreta(t.dataset.tipo);
  }));
}

function conectarSugerencia() {
  const boton = document.getElementById('boton-sugerir');
  const panel = document.getElementById('panel-sugerencia');
  boton.addEventListener('click', () => { panel.hidden = !panel.hidden; });
}

pintarEncabezado();
pintarMesa();
pintarSelectores();
pintarHistorial();
pintarLibreta('sospechoso');
pintarProgreso();
pintarMano();
conectarTabs();
conectarSugerencia();
