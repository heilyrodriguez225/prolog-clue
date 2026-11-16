// La página de la mesa: pinta el estado que da la API (ver PLAN.md §3, "La API web")
// y manda las jugadas. El aspecto es de la maqueta; aquí solo está el comportamiento.

const TIPOS = { sospechoso: 'Sospechoso', arma: 'Arma', lugar: 'Lugar' };
const TIPOS_PL = { sospechoso: 'Sospechosos', arma: 'Armas', lugar: 'Lugares' };
const ASIENTOS = ['norte', 'oeste', 'este', 'sur'];
const PALETA_IA = ['var(--vino)', 'var(--arma)', 'var(--lugar)', 'var(--morado)'];
const NIVELES = { facil: 'Fácil', media: 'Medio', dificil: 'Difícil', azar: 'Azar' };
const PERIODO_MS = 700;

const ID = location.hash.slice(1);
let CARTAS = [];          // las 21 cartas, de /api/config
let estado = null;        // última foto recibida
let tipoLibreta = 'sospechoso';
let clavePendiente = null; // evita reabrir el mismo diálogo en cada consulta

const el = (tag, clase, html) => {
  const e = document.createElement(tag);
  if (clase) e.className = clase;
  if (html !== undefined) e.innerHTML = html;
  return e;
};
// Los nombres los escribe el usuario: nunca van como HTML sin escapar.
const esc = (t) => String(t).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const porId = (id) => CARTAS.find((c) => c.id === id);
const nombreCarta = (id) => (porId(id) ? porId(id).nombre : id);
const nombresCartas = (ids) => ids.map(nombreCarta).join(' · ');

async function api(metodo, ruta, cuerpo) {
  const r = await fetch(ruta, {
    method: metodo,
    headers: cuerpo ? { 'Content-Type': 'application/json' } : {},
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  const datos = await r.json();
  if (!r.ok) throw Object.assign(new Error(datos.mensaje || 'Error'), { estado: r.status, codigo: datos.error });
  return datos;
}

// ---------- Nombres ----------

function nombreJugador(id) {
  if (id === 1) return 'Tú';
  const j = estado.jugadores.find((x) => x.id === id);
  return j ? j.nombre : `Jugador ${id}`;
}

// ---------- Mesa ----------

function carta(c, enMano) {
  const e = el('article', `carta ${c.tipo}`);
  e.innerHTML = `
    <div class="rotulo">${TIPOS[c.tipo]}</div>
    <div class="arte">
      <span class="mono">${esc(c.nombre[0])}</span>
      <img src="img/cartas/${c.id}.png" alt="" onerror="this.remove()">
    </div>
    <div class="pie">
      <span class="titulo">${esc(c.nombre)}</span>
      ${enMano ? '<span class="posesion">✓ En tu poder</span>' : ''}
    </div>`;
  return e;
}

// Al terminar la partida se enseñan las cartas de cada rival.
function manoRevelada(id) {
  const f = estado.fin;
  if (estado.estado !== 'fin' || !f || !f.manos) return '';
  const m = f.manos.find((x) => x.jugador === id);
  if (!m) return '';
  return `<div class="mano-revelada">${m.cartas.map((c) => `<span class="mini ${porId(c) ? porId(c).tipo : ''}">${esc(nombreCarta(c))}</span>`).join('')}</div>`;
}

function pintarMesa() {
  const ovalo = document.getElementById('mesa-ovalo');
  ovalo.querySelectorAll('.asiento').forEach((a) => a.remove());
  const ias = estado.jugadores.slice(1);
  ovalo.dataset.rivales = ias.length;
  ias.forEach((j, i) => {
    const pos = ias.length === 2 ? ['oeste', 'este'][i] : ASIENTOS[i];
    const activo = estado.estado === 'jugando' && estado.turno === j.id;
    const e = el('div', `asiento ${pos}${activo ? ' activo' : ''}${j.eliminado ? ' eliminado' : ''}`);
    e.style.setProperty('--c', PALETA_IA[i % PALETA_IA.length]);
    e.innerHTML = `
      <div class="asiento-cab">
        <div class="avatar">${esc(j.nombre[0])}</div>
        <div>
          <div class="nombre">${esc(j.nombre)} (IA)</div>
          <div class="rol">${NIVELES[j.nivel] ?? j.nivel}</div>
        </div>
        <span class="cartas-n">${j.cartas} cartas</span>
      </div>
      <div class="estado">${j.eliminado ? 'Eliminado' : activo ? 'Pensando…' : 'En espera'}</div>${manoRevelada(j.id)}`;
    ovalo.appendChild(e);
  });
}

// El selector de ritmo muestra el de la partida (el más cercano de los tres).
function pintarRitmo() {
  const sel = document.getElementById('ritmo');
  if (document.activeElement === sel) return;
  if (estado.ritmo === 'manual') { sel.value = 'manual'; return; }
  if (typeof estado.ritmo !== 'number') return;
  const opciones = [...sel.options].filter((o) => o.value !== 'manual').map((o) => Number(o.value));
  const cerca = opciones.reduce((a, b) => (Math.abs(b - estado.ritmo) < Math.abs(a - estado.ritmo) ? b : a));
  sel.value = String(cerca);
}

function pintarEncabezado() {
  let texto;
  if (estado.estado === 'fin') texto = 'Fin de la partida';
  else if (estado.estado === 'jugando' && estado.turno === 1) texto = 'los rivales'; // el turno se actualiza con la siguiente jugada
  else texto = nombreJugador(estado.turno);
  document.getElementById('pildora-turno-nombre').textContent = texto;
  const aviso = document.getElementById('aviso-turno');
  const p = estado.pendiente;
  const tuTurno = estado.estado === 'esperando' && p && p.tipo === 'accion';
  const refutas = estado.estado === 'esperando' && p && p.tipo === 'carta';
  const siguiente = estado.estado === 'esperando' && p && p.tipo === 'siguiente';
  aviso.textContent = siguiente ? 'Pulsa «Siguiente» para continuar.'
    : estado.modo === 'espectador' && estado.estado !== 'fin' ? 'Modo demo: observas pensar a la IA.'
    : refutas ? 'Tienes que refutar: elige una carta.'
    : tuTurno ? 'Es tu turno: sugiere o acusa.' : estado.estado === 'fin' ? '' : 'Esperando a los demás…';
  aviso.classList.toggle('tu-turno', tuTurno);
}

function pintarMano() {
  const cont = document.getElementById('mano');
  cont.innerHTML = '';
  document.getElementById('mano-cuenta').textContent = `${estado.mano.length} cartas`;
  for (const id of estado.mano) if (porId(id)) cont.append(carta(porId(id), true));
}

// ---------- Historial ----------

// Quién respondió a una sugerencia, turno a turno: quién no tenía nada y quién refutó.
// La carta concreta solo se ve si te la enseñaron a ti (las demás son privadas hasta el final).
function detalleSugerencia(h) {
  const sin = h.respuestas.filter((r) => r.resultado === 'no_pudo').map((r) => nombreJugador(r.jugador));
  const refuto = h.respuestas.find((r) => r.resultado === 'refuto');
  const partes = [];
  if (sin.length) partes.push(`sin cartas para refutar: ${sin.join(', ')}`);
  if (!refuto) partes.push('nadie pudo refutar');
  else if (refuto.jugador === 1) partes.push('Tú refutaste');
  else {
    let t = `${nombreJugador(refuto.jugador)} refutó`;
    if (h.carta_vista) t += ` y te enseñó ${nombreCarta(h.carta_vista.carta)}`;
    else t += ' (carta en privado)';
    partes.push(t);
  }
  return partes.join(' · ');
}

function textoEntrada(h) {
  if (h.tipo === 'sugerencia') return { texto: `sugiere ${nombresCartas(h.cartas)}`, res: detalleSugerencia(h) };
  const quien = h.quien === 1 ? 'Tú' : nombreJugador(h.quien);
  return { texto: `acusa ${nombresCartas(h.cartas)}`, res: h.resultado === 'acierta' ? '¡Acertó!' : `${quien} falló y queda eliminado` };
}

// Una pestaña por turno. Si no has elegido ninguna, se sigue el último turno.
let turnoElegido = null;

// La rueda del ratón desplaza las pestañas en horizontal.
let ruedaPuesta = false;
function ruedaEnPestanas(tabs) {
  if (ruedaPuesta) return;
  ruedaPuesta = true;
  tabs.addEventListener('wheel', (ev) => {
    if (Math.abs(ev.deltaY) > Math.abs(ev.deltaX) && tabs.scrollWidth > tabs.clientWidth) {
      tabs.scrollLeft += ev.deltaY;
      ev.preventDefault();
    }
  }, { passive: false });
}

function pintarHistorial() {
  const tabs = document.getElementById('turnos-tabs');
  ruedaEnPestanas(tabs);
  const detalle = document.getElementById('turno-detalle');
  const titulo = document.getElementById('actividad-ultimo');
  const hist = estado.historial;
  tabs.innerHTML = '';
  if (hist.length === 0) {
    titulo.textContent = 'Todavía no ha pasado nada';
    detalle.innerHTML = '';
    return;
  }
  titulo.textContent = `Historial · ${hist.length} ${hist.length === 1 ? 'turno' : 'turnos'}`;
  const ultimo = hist[hist.length - 1].n;
  const sel = turnoElegido !== null && turnoElegido < ultimo ? turnoElegido : ultimo;
  for (const h of hist) {
    const b = el('button', `tab-turno${h.n === sel ? ' sel' : ''}${h.tipo === 'acusacion' ? ' acusa' : ''}`,
                 `<span class="n">${h.n}</span><span class="q">${esc(nombreJugador(h.quien))}</span>`);
    b.type = 'button';
    b.setAttribute('role', 'tab');
    b.setAttribute('aria-selected', String(h.n === sel));
    b.title = `Turno ${h.n}`;
    b.onclick = () => { turnoElegido = h.n === ultimo ? null : h.n; pintarHistorial(); };
    tabs.append(b);
  }
  detalle.innerHTML = ventanaSiguiente(sel);
  const activa = tabs.querySelector('.sel');
  if (activa) activa.scrollIntoView({ block: 'nearest', inline: 'nearest' });
}

// ---------- Libreta (la asistida completa es la #20) ----------

// Estados de la libreta: descartado (no está en el sobre), segura (seguro: está en el sobre),
// sospechoso (más probable que la media de su tipo) y sinpista.
function estadosDeLibreta() {
  const libreta = estado.libreta;
  const res = {};
  for (const c of CARTAS) {
    const e = libreta && libreta.find((l) => l.carta === c.id);
    if (e) res[c.id] = { clase: e.estado === 'descartada' ? 'descartado' : e.estado === 'sobre' ? 'segura' : 'sinpista', pct: e.probabilidad };
    else res[c.id] = { clase: estado.mano.includes(c.id) ? 'descartado' : 'sinpista', pct: null }; // sin asistente solo sabes tu mano
  }
  // Más probable que la media de su tipo (la media es 100 / cartas que quedan) = sospechoso.
  for (const tipo of Object.keys(TIPOS)) {
    const vivas = CARTAS.filter((c) => c.tipo === tipo && res[c.id].clase === 'sinpista' && res[c.id].pct !== null);
    const media = vivas.length ? vivas.reduce((t, c) => t + res[c.id].pct, 0) / vivas.length : 0;
    for (const c of vivas) if (res[c.id].pct > media + 0.5) res[c.id].clase = 'sospechoso';
  }
  return res;
}

function pintarLibreta() {
  const lista = document.getElementById('libreta-lista');
  lista.innerHTML = '';
  document.getElementById('libreta-cab-titulo').textContent = TIPOS_PL[tipoLibreta];
  const delTipo = CARTAS.filter((c) => c.tipo === tipoLibreta);
  document.getElementById('libreta-cab-total').textContent = `${delTipo.length} posibles`;
  const estados = estadosDeLibreta();
  const sinAsistente = !estado.libreta;
  for (const c of delTipo) {
    const { clase, pct } = estados[c.id];
    const icono = clase === 'descartado' ? '☒' : clase === 'segura' ? '✔' : clase === 'sospechoso' ? '？' : '';
    const porcentaje = clase === 'descartado' || pct === null ? '' : `${pct.toFixed(0)} %`;
    lista.append(el('div', `fila-carta ${clase}`, `<span class="estado-ico">${icono}</span><span class="nombre">${esc(c.nombre)}</span><span class="pct">${porcentaje}</span>`));
  }
  if (sinAsistente) lista.append(el('p', 'nota-asistente', 'Asistente apagado: la libreta solo marca tus cartas. Deduce tú.'));
  const total = CARTAS.length - 3;
  const descartadas = Object.values(estados).filter((e) => e.clase === 'descartado').length;
  document.getElementById('progreso-txt').textContent = `${descartadas} de ${total} descartadas`;
  document.getElementById('progreso-rel').style.width = `${Math.min(100, (descartadas / total) * 100)}%`;
  const espectador = estado.modo === 'espectador';
  document.getElementById('libreta-titulo').textContent = espectador ? 'IA (jugador 1)' : estado.jugadores[0].nombre;
}

// ---------- Acciones ----------

function pintarSelectores() {
  const cont = document.getElementById('selectores');
  cont.innerHTML = '';
  for (const tipo of Object.keys(TIPOS)) {
    const opciones = CARTAS.filter((c) => c.tipo === tipo).map((c) => `<option value="${c.id}">${esc(c.nombre)}</option>`).join('');
    cont.append(el('div', 'slot', `<label>${TIPOS[tipo]}</label><select data-tipo="${tipo}">${opciones}</select>`));
  }
}

function seleccion() {
  return [...document.querySelectorAll('#selectores select')].map((s) => s.value);
}

function actualizarControles() {
  const tuTurno = estado.estado === 'esperando' && estado.pendiente && estado.pendiente.tipo === 'accion';
  for (const id of ['enviar-sugerencia', 'enviar-acusacion', 'boton-sugerir']) {
    document.getElementById(id).disabled = !tuTurno;
  }
  document.querySelectorAll('#selectores select').forEach((s) => { s.disabled = !tuTurno; });
  if (!tuTurno) document.getElementById('panel-sugerencia').hidden = true;
}

async function enviarAccion(tipo) {
  try {
    await api('POST', `/api/partida/${ID}/accion`, { tipo, cartas: seleccion() });
    await consultar(true);
  } catch (e) {
    alert(e.message);
  }
}

function confirmarAcusacion() {
  const cartas = seleccion();
  abrirDialogo(`
    <h2>¿Acusar?</h2>
    <p>Vas a acusar a: <strong>${esc(nombresCartas(cartas))}</strong>.</p>
    <p>Si te equivocas quedas eliminado y la partida termina.</p>
    <div class="botones">
      <button class="primario" id="si-acusar">Sí, acusar</button>
      <button id="no-acusar">No, volver</button>
    </div>`);
  document.getElementById('no-acusar').onclick = cerrarDialogo;
  document.getElementById('si-acusar').onclick = () => { cerrarDialogo(); enviarAccion('acusar'); };
}

// ---------- Diálogos: refutar y fin ----------

function abrirDialogo(html) {
  const d = document.getElementById('dialogo');
  d.innerHTML = html;
  if (!d.open) d.showModal();
}
function cerrarDialogo() {
  const d = document.getElementById('dialogo');
  if (d.open) d.close();
}

// Paso a paso: cada cosa que ocurre sale en su ventana y la partida espera.
function textoRespuestas(h) {
  return h.respuestas.map((r) => {
    const quien = nombreJugador(r.jugador);
    if (r.resultado === 'no_pudo') return `<li class="no">✗ <strong>${esc(quien)}</strong> no ${r.jugador === 1 ? 'tienes' : 'tiene'} ninguna de las tres cartas</li>`;
    if (r.jugador === 1) return `<li class="si">✓ <strong>Tú</strong> refutaste enseñando una carta</li>`;
    const vista = h.carta_vista ? ` y te enseñó <strong>${esc(nombreCarta(h.carta_vista.carta))}</strong>` : ' (la carta es privada)';
    return `<li class="si">✓ <strong>${esc(quien)}</strong> refutó${vista}</li>`;
  }).join('');
}

function ventanaSiguiente(n) {
  const h = estado.historial.find((x) => x.n === n);
  if (!h) return '<h2>…</h2>';
  if (h.tipo === 'sugerencia') {
    const nadie = !h.respuestas.some((r) => r.resultado === 'refuto');
    return `
      <p class="turno-ventana">Turno ${h.n}</p>
      <h2>${esc(nombreJugador(h.quien))} sugiere</h2>
      <p class="cartas-ventana">${esc(nombresCartas(h.cartas))}</p>
      <ul class="respuestas">${textoRespuestas(h)}${nadie ? '<li class="no">Nadie pudo refutar</li>' : ''}</ul>`;
  }
  const quien = nombreJugador(h.quien);
  const res = h.resultado === 'acierta' ? '¡Acertó!' : `${quien} se equivocó y queda eliminado`;
  return `
    <p class="turno-ventana">Turno ${h.n}</p>
    <h2>${esc(quien)} acusa</h2>
    <p class="cartas-ventana">${esc(nombresCartas(h.cartas))}</p>
    <p class="res-acusacion">${esc(res)}</p>`;
}

function pintarSiguiente() {
  const p = estado.pendiente;
  const abierta = clavePendiente && clavePendiente.startsWith('sig');
  if (estado.estado === 'fin' || !p || p.tipo !== 'siguiente') {
    if (abierta) { cerrarDialogo(); clavePendiente = null; }
    return false;
  }
  const clave = `sig${p.n}`;
  if (clavePendiente === clave) return true;               // ya está abierta
  clavePendiente = clave;
  abrirDialogo(`${ventanaSiguiente(p.n)}
    <div class="botones"><button class="primario" id="siguiente">Siguiente ›</button></div>`);
  const b = document.getElementById('siguiente');
  b.focus();
  b.onclick = async () => {
    b.disabled = true;
    try {
      await api('POST', `/api/partida/${ID}/siguiente`);
    } catch (e) {
      if (e.estado !== 409) alert(e.message);               // 409: ya se había dado
    }
    clavePendiente = null;
    cerrarDialogo();
    await consultar(true);
  };
  return true;
}

function pintarPendiente() {
  if (pintarSiguiente()) return;
  const p = estado.pendiente;
  if (estado.estado === 'fin' || !p || p.tipo !== 'carta') {
    if (clavePendiente && clavePendiente.startsWith('carta')) cerrarDialogo();
    if (!p && clavePendiente && clavePendiente.startsWith('carta')) clavePendiente = null;
    return;
  }
  const clave = `carta${estado.version}`;
  if (clavePendiente && clavePendiente.startsWith('carta')) return; // ya está abierto
  clavePendiente = clave;
  const botones = p.candidatas.map((c) => `<button class="primario" data-carta="${c}">${esc(nombreCarta(c))}</button>`).join('');
  abrirDialogo(`
    <h2>Tienes que refutar</h2>
    <p>${esc(nombreJugador(p.sugerencia.quien))} sugiere: <strong>${esc(nombresCartas(p.sugerencia.cartas))}</strong>.</p>
    <p>¿Qué carta enseñas?</p>
    <div class="opciones">${botones}</div>`);
  document.querySelectorAll('#dialogo [data-carta]').forEach((b) => {
    b.onclick = async () => {
      try {
        await api('POST', `/api/partida/${ID}/carta`, { carta: b.dataset.carta });
        clavePendiente = null;
        cerrarDialogo();
        await consultar(true);
      } catch (e) {
        alert(e.message);
      }
    };
  });
}

function manosEnDialogo(f) {
  if (!f.manos) return '';
  const filas = f.manos.filter((m) => m.jugador !== 1).map((m) => {
    const ia = estado.jugadores.find((x) => x.id === m.jugador);
    const quien = ia ? `${ia.nombre} (${NIVELES[ia.nivel] ?? ia.nivel})` : nombreJugador(m.jugador);
    return `<li><strong>${esc(quien)}</strong>: ${esc(nombresCartas(m.cartas))}</li>`;
  }).join('');
  return `<p class="manos-titulo">Las cartas de cada rival:</p><ul class="manos-fin">${filas}</ul>`;
}

function pintarFin() {
  if (estado.estado !== 'fin' || !estado.fin) return;
  if (clavePendiente === 'fin') return;
  clavePendiente = 'fin';
  const f = estado.fin;
  let titulo, motivo;
  if (estado.modo === 'espectador') {
    titulo = f.ganador === 1 ? 'La IA ha ganado' : f.ganador === null ? 'La IA se ha equivocado' : `Gana ${nombreJugador(f.ganador)}`;
    motivo = f.ganador === 1 ? 'Acusó con la solución deducida: mira su libreta.' : 'La partida termina aquí.';
  } else if (f.ganador === 1) {
    titulo = '¡Has ganado!';
    motivo = f.motivo === 'acierta' ? 'Acusaste correctamente.' : 'Eres el único que queda sin eliminar.';
  } else if (f.ganador === null) {
    titulo = 'Has perdido';
    motivo = 'Te equivocaste al acusar y quedaste eliminado, así que la partida termina aquí.';
  } else {
    titulo = `Gana ${nombreJugador(f.ganador)}`;
    motivo = f.motivo === 'acierta' ? 'Acusó correctamente.' : 'Es el único que queda sin eliminar.';
  }
  abrirDialogo(`
    <h2>${esc(titulo)}</h2>
    <p>${esc(motivo)}</p>
    <p>El sobre era: <strong>${esc(nombresCartas(f.sobre))}</strong>.</p>
    ${manosEnDialogo(f)}
    <div class="botones">
      <button class="primario" id="otra">Nueva partida</button>
      <button id="ver-mesa">Ver la mesa</button>
    </div>`);
  document.getElementById('otra').onclick = () => { location.href = 'inicio.html'; };
  document.getElementById('ver-mesa').onclick = cerrarDialogo;
}

// ---------- Consultar el estado ----------

function pintar() {
  pintarEncabezado();
  pintarRitmo();
  pintarMesa();
  pintarMano();
  pintarHistorial();
  pintarLibreta();
  actualizarControles();
  pintarPendiente();
  pintarFin();
}

async function consultar(forzar) {
  try {
    const v = !forzar && estado ? `?version=${estado.version}` : '';
    const nuevo = await api('GET', `/api/partida/${ID}${v}`);
    if (nuevo.sin_cambios) return;
    estado = nuevo;
    pintar();
  } catch (e) {
    if (e.estado === 404) {
      alert('Esa partida ya no existe.');
      location.href = 'inicio.html';
    }
    // Un fallo de red es pasajero: se vuelve a intentar en la siguiente consulta.
  }
}

function conectar() {
  document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((x) => x.classList.remove('sel'));
    t.classList.add('sel');
    tipoLibreta = t.dataset.tipo;
    if (estado) pintarLibreta();
  }));
  const panel = document.getElementById('panel-sugerencia');
  document.getElementById('boton-sugerir').addEventListener('click', () => { panel.hidden = !panel.hidden; });
  document.getElementById('ritmo').addEventListener('change', async (ev) => {
    const v = ev.target.value;
    try { await api('POST', `/api/partida/${ID}/ritmo`, { segundos: v === 'manual' ? 'manual' : Number(v) }); }
    catch (e) { alert(e.message); }
  });
  document.getElementById('enviar-sugerencia').addEventListener('click', () => enviarAccion('sugerir'));
  document.getElementById('enviar-acusacion').addEventListener('click', confirmarAcusacion);
  document.getElementById('dialogo').addEventListener('cancel', (ev) => {
    // Con Esc no se puede saltar la obligación de refutar.
    if (estado && estado.pendiente && ['carta', 'siguiente'].includes(estado.pendiente.tipo)) ev.preventDefault();
  });
}

async function empezar() {
  if (!ID) { location.href = 'inicio.html'; return; }
  CARTAS = (await api('GET', '/api/config')).cartas;
  pintarSelectores();
  conectar();
  await consultar(true);
  setInterval(() => {
    if (!estado || estado.estado !== 'fin') consultar(false);
  }, PERIODO_MS);
}

empezar();
