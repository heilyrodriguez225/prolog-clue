# Plan de Sherlog

El *qué* y el *por qué* de cada fase. El *ahora* está en el tablero Scrumban.

## §1 La idea

Sherlog es un juego de deducción al estilo Clue: tú contra 2–4 oponentes de IA que razonan en Prolog. Lo importante del proyecto es **cómo piensa la IA**: cada jugada se convierte en una restricción lógica y el motor CLP(FD) deduce qué cartas pueden estar en el sobre.

Proyecto final de Programación Declarativa: una persona, **un mes** (26 oct – 22 nov 2026), una fase por semana.

## §2 Reglas de Sherlog

Basadas en Clue, simplificadas para que todo el esfuerzo vaya a la parte declarativa.

| Regla | Decisión |
|---|---|
| Mazo | 6 sospechosos, 6 armas, 9 lugares (21 cartas). Ver "Las cartas" |
| Sobre | 1 carta de cada tipo, elegida al azar |
| Jugadores | 1 humano + 2–4 IAs (3–5 en total), **3 IAs por defecto**. Las 18 cartas restantes se reparten lo más parejo posible |
| Tablero | **No hay tablero ni dados.** En su turno, cada jugador sugiere cualquier lugar |
| Sugerencia | "Fue X con Y en Z". Se pregunta en orden a los siguientes jugadores; el primero que tenga alguna de las tres cartas enseña **una** solo a quien sugirió |
| Lo que ven los demás | Quién refutó y quién no pudo, pero no la carta enseñada |
| Acusación | Si acierta, gana. Si falla, queda eliminado pero sigue refutando. **Excepción: si es el humano, la partida termina**: no tiene sentido que siga solo entre IAs mientras él mira |

**Por qué 2–4 IAs:** con 4 jugadores cada uno tiene 4 o 5 cartas y la partida queda equilibrada. Con 6, las partidas se alargan, la IA difícil es más lenta (hay más respuestas posibles para cada sugerencia) y el torneo tiene muchas más combinaciones. El motor es genérico para N jugadores, así que ampliar a 5 IAs es cambiar un número.

### Las cartas

| Sospechosos (6) | Armas (6) | Lugares (9) |
|---|---|---|
| Chef Canela | Trofeo | Biblioteca |
| Entrenador Cobalto | Veneno | Cocina |
| Señora Coral | Cuerda | Sala de video |
| Jardinero Verde | Daga | Piscina |
| Doctora Violeta | Revólver | Comedor |
| Señorita Perla | Tijeras | Estudio |
| | | Bodega |
| | | Gimnasio |
| | | Jardín |

En el código, cada carta es un átomo sin tildes ni espacios (`chef_canela`, `sala_de_video`…), y el nombre para mostrar se guarda aparte.

### El estado de la partida

El estado es un **término que se pasa de turno en turno**, sin `assert`:

```prolog
partida(Sobre, Manos, Turno, Eliminados, Historial)
```

| Argumento | Contenido |
|---|---|
| `Sobre` | `sobre(Sospechoso, Arma, Lugar)` |
| `Manos` | Lista `Jugador-Cartas` |
| `Turno` | Jugador al que le toca |
| `Eliminados` | Jugadores que acusaron mal |
| `Historial` | Lista, de la más antigua a la más reciente, de los eventos públicos: `sugerencia/3` y `acusacion/3` (ver §3) |

Cada turno recibe el estado anterior y devuelve uno nuevo. **Por qué:** es más declarativo, se prueba fácilmente con tests y evita que `assert` pierda las restricciones CLP(FD) de la IA (al guardar un término con `assert` se copia sin sus restricciones). Solo el servidor web (F3) guarda la partida en curso con `assert` o `nb_setval`.

## §3 Arquitectura

```
src/
  juego.pl        cartas, reparto y partida nueva
  deduccion.pl    conocimiento de cada IA como restricciones CLP(FD)
  jugador.pl      los jugadores y el protocolo con el que juegan (ver abajo)
  turnos.pl       el bucle de la partida: turnos, sugerencias, acusaciones y fin
  ia.pl           lo que decide cada nivel de IA, sobre listas de cartas
  explicacion.pl  metaintérprete: por qué la IA sabe lo que sabe
  consola.pl      entrada y salida por la terminal del jugador humano
  sherlog.pl      una partida completa contra las IAs, por la terminal
  jugar.pl        el programa: swipl src/jugar.pl
  puente.pl       el jugador web: cola de jugadas y foto del estado (entre hilos)
  servidor.pl     API HTTP/JSON (library(http)) y la página de web/
  servir.pl       el programa: swipl src/servir.pl [puerto]
web/              página del juego (HTML, CSS, JS)
tests/            tests con plunit
```

La interfaz web no tiene lógica de juego: solo muestra el estado y envía las acciones del jugador. **Todas las reglas y la IA viven en Prolog.**

**Dependencias entre módulos.** Cada uno importa solo a los de su izquierda, para que no haya ciclos:

```
juego.pl  ←  deduccion.pl  ←  ia.pl  ←  puente.pl  ←  jugador.pl  ←  turnos.pl  ←  sherlog.pl  ←  jugar.pl
                                                                    turnos.pl  ←  servidor.pl  ←  servir.pl
              juego.pl  ←  consola.pl  ↗  (jugador.pl también importa consola.pl)
```

Por eso el bucle de la partida no vive en `juego.pl`: `jugador.pl` ya importa `juego.pl` (para las cartas) y el bucle necesita importar `jugador.pl`.

La consola tiene el mismo cuidado. `consola.pl` solo conoce las cartas (`juego.pl`) y no sabe nada de jugadores ni del bucle, así que `jugador.pl` puede usarla para el tipo `humano` sin crear un ciclo. La lógica de la partida por terminal vive en `sherlog.pl`; `jugar.pl` es solo el programa que la arranca. Se separan porque cargar un archivo con `initialization(main, main)` lo ejecuta, y los tests necesitan cargar la lógica sin que empiece una partida.

### El protocolo de jugador

El bucle de la partida (`juego.pl`) solo habla con los jugadores mediante un **protocolo común**, sin saber de qué tipo es cada uno (azar, humano, fácil, media o difícil).

**Dos estados separados.** La partida (`partida/5`, ver §2) guarda lo que es verdad: el sobre, las manos y lo público. Los jugadores van en una **lista aparte**, que el bucle pasa de turno en turno:

```prolog
jugador(Id, Tipo, Memoria)
```

| Tipo | Memoria | Qué guarda |
|---|---|---|
| `azar`, `humano` | `[]` | Nada: el humano ve por la consola y el de azar no aprende |
| `facil` | `vistas(Cartas)` | Las cartas que ha visto |
| `media`, `dificil` | `mente(K, Mostradas)` | `K`: el modelo CLP(FD) de `deduccion.pl`, con sus restricciones. `Mostradas`: las cartas que ha enseñado y a quién |

La memoria **nunca se guarda con `assert`** (se perderían las restricciones). Cada operación devuelve el jugador con la memoria actualizada.

**Un jugador nunca recibe la partida.** Tendría el sobre y las manos de los demás. Recibe su **vista**, que extrae `vista_de/3`:

```prolog
vista(Mano, Eliminados, Historial)
```

**Las operaciones** (`jugador.pl`), cada una con una cláusula por tipo de jugador:

| Operación | Cuándo | Devuelve |
|---|---|---|
| `elegir_accion(J, Vista, Accion, J1)` | Le toca jugar | `sugerir(S, A, L)` o `acusar(S, A, L)` |
| `elegir_carta_a_mostrar(J, Sugerencia, Candidatas, Carta, J1)` | Tiene que refutar | Una de las `Candidatas`, que calcula el bucle y son las cartas de la sugerencia que tiene |
| `observar(J, Evento, J1)` | Ocurre algo que puede ver | El jugador con la memoria actualizada |

`Sugerencia` es `sugerencia(Quien, [S, A, L])`.

**Los eventos.** Hay dos públicos y uno privado:

| Evento | Tipo | Qué dice |
|---|---|---|
| `sugerencia(Quien, [S, A, L], Respuestas)` | Público | `Quien` sugiere. `Respuestas` son, en orden de turno, los jugadores a los que se preguntó: `no_pudo(J)` si no tenía ninguna de las tres cartas y, si alguien refutó, la lista termina con `refuto(J)` |
| `acusacion(Quien, [S, A, L], Resultado)` | Público | `Resultado` es `acierta` o `falla` |
| `carta_vista(Refutador, Carta)` | **Privado** | La carta que enseñó el `Refutador` |

**Quién ve qué:**

| Quién | Ve |
|---|---|
| **Todos los jugadores** | Cada `sugerencia` (quién, qué cartas, quién no pudo y quién refutó) y cada `acusacion` |
| **Solo el que sugirió** | La `carta_vista` que le enseñaron |
| **Nadie más** | Qué carta enseñó el refutador, ni el sobre, ni las manos ajenas |

Se entregan con dos predicados que **hacen cumplir la regla**: `observar_todos/3` solo acepta eventos públicos y `observar_a/4` solo privados. Entregar mal un evento da un error, no un fallo silencioso.

**El historial** (`Historial` en la partida) guarda solo los eventos públicos, de la más antigua a la más reciente. La `carta_vista` nunca entra.

**Qué hace la IA media con cada evento** (`media_observar/3` en `ia.pl`, hecho en #14):

| Evento | Observación en `deduccion.pl` |
|---|---|
| `no_pudo(J)` de una sugerencia | `no_refuto(K, J, Cartas)` |
| `refuto(J)` y no soy quien sugirió | `refuto(K, J, Cartas)`: tiene al menos una, no sé cuál |
| `carta_vista(J, Carta)` | `mostro(K, J, Carta)` |
| `acusacion(_, Cartas, falla)` | `acusacion_fallida(K, Cartas)`: esas tres no son, juntas, las del sobre |

Lo que le ocurre a la propia IA no aporta nada: si ella no pudo refutar o refutó, ya lo sabe. Y cuando ella sugiere y alguien refuta, el `refuto(J)` público no se traduce, porque la `carta_vista` que le llega aparte dice más.

**Cómo juega cada tipo** hoy (el protocolo ya funciona; el comportamiento propio llega con cada tarea):

| Tipo | Hoy | Después |
|---|---|---|
| `azar` | Al azar, siempre | (es el nivel más bajo, la referencia con la que comparar a los demás) |
| `humano` | **Hecho (#12):** pregunta por la terminal y cuenta lo que ocurre | |
| `facil` | **Hecho (#13):** recuerda las cartas que le enseñan, sugiere entre las que no ha visto y acusa cuando le queda una sola de cada tipo | |
| `media` | **Hecho (#14):** convierte en restricciones todo lo que ve, deduce qué cartas pueden estar en el sobre, sugiere entre ellas, acusa solo cuando es seguro y, al refutar, **hecho (#15)** procura revelar lo menos posible: repite la carta que ya enseñó a ese jugador | |
| `dificil` | Al azar | Además elige la mejor sugerencia (#21) |

### El bucle de la partida (`turnos.pl`)

`jugar(Partida, Jugadores, Resultado)` juega una partida de principio a fin como una **recursión**: cada llamada hace un turno y se vuelve a llamar con el estado nuevo, sin `assert` ni estado global.

En cada turno:

1. Si queda un solo jugador sin eliminar, gana (`ultimo`).
2. Si no, se le pide su acción al jugador al que le toca (`accion_del_turno/4`): recibe solo su vista y la acción se valida.
3. **Sugerir:** se pregunta en orden circular a los demás, también a los eliminados; el primero que tenga alguna de las tres cartas refuta y se deja de preguntar. El evento `sugerencia/3` va a todos y al historial; la `carta_vista/2`, solo al que sugirió.
4. **Acusar:** si coincide con el sobre gana (`acierta`). Si no, queda eliminado (sigue refutando, pero ya no juega turno). El evento `acusacion/3` va a todos y al historial.
5. El turno pasa al siguiente jugador en círculo que no esté eliminado.

El resultado es `fin(Ganador, Motivo, Partida, Jugadores)`, con el estado final y el historial completo.

El bucle **solo** habla con los jugadores mediante el protocolo de arriba. No usa `deduccion.pl`, no consulta la memoria de nadie y no guarda estado global; los tests lo comprueban leyendo el código del módulo.

### La API web (diseño)

La página y el juego hablan por HTTP con mensajes JSON. Esto es el **diseño**; se implementa en `servidor.pl` (#18) y en la página (#19). La página es libre de verse como quiera: lo único que necesita de Prolog es lo que describe esta sección.

**Cómo espera el servidor al humano, sin tocar el bucle.** HTTP no espera: cada petición recibe una respuesta. Pero el bucle de la partida (`jugar/4`) es una recursión que se queda parada hasta que el humano decide. Se resuelve con **un hilo por partida**:

- Cada partida corre en su propio hilo, con `jugar/4` y la opción `termina_si_cae(1)`.
- El humano es un tipo de jugador más, **`web`**, que hace lo mismo que `humano`: `elegir_accion/4`, `elegir_carta_a_mostrar/5` y `observar/3`. En vez de preguntar por la terminal, **espera un mensaje en una cola**; las peticiones HTTP lo dejan allí.
- Mientras espera (y con cada evento que ve), el jugador `web` deja una **foto** del estado en un sitio compartido. Las peticiones `GET` leen esa foto, sin molestar al hilo de la partida.
- Todo lo que cruza entre hilos son **datos planos** (listas, cadenas, números), nunca términos con restricciones. El conocimiento CLP(FD) vive y se consulta **dentro del hilo de la partida**.
- Como la consola, no cambia `turnos.pl` ni el protocolo de jugador.

**Rutas.** Todas devuelven JSON. El humano es siempre el jugador 1.

| Ruta | Para qué |
|---|---|
| `GET /api/config` | Lo que la página necesita saber antes de empezar, para no repetirlo en JavaScript: las 21 cartas (`id`, `nombre`, `tipo`), los niveles que existen y los límites de rivales (2 a 4). La imagen de cada carta es `img/cartas/{id}.png` |
| `POST /api/partida` | Crear una partida. Cuerpo: `{"nombre": "Ana", "rivales": [{"nivel": "facil"}, {"nivel": "media"}], "asistente": true, "modo": "jugar"}`. Con `"modo": "espectador"` (demo) juega la IA media en tu lugar y la libreta es la suya; necesita `asistente`. De 2 a 4 rivales, **cada uno con su nivel**. Devuelve el estado con el `id` de la partida |
| `GET /api/partida/{id}` | El estado actual. Con `?version=N` y sin cambios desde entonces, devuelve solo `{"version": N, "sin_cambios": true}` |
| `POST /api/partida/{id}/accion` | Hacer tu jugada: `{"tipo": "sugerir", "cartas": ["chef_canela", "trofeo", "biblioteca"]}` o `{"tipo": "acusar", ...}` |
| `POST /api/partida/{id}/carta` | Elegir qué carta enseñar al refutar: `{"carta": "trofeo"}` |
| `DELETE /api/partida/{id}` | Abandonar la partida (se detiene su hilo) |
| `GET /` y archivos de `web/` | La página |

Los `POST` devuelven el estado enseguida; **la página consulta `GET` cada poco** (unos 700 ms) mientras juegan las IAs. Con `?version=N` no se transfiere nada si no ha cambiado.

**El estado.** Es lo único que ve la página:

```json
{
  "id": "a3f9c2",
  "version": 17,
  "estado": "esperando",
  "turno": 1,
  "jugadores": [
    {"id": 1, "nombre": "Ana",  "nivel": null,    "cartas": 5, "eliminado": false},
    {"id": 2, "nombre": "Beto", "nivel": "media", "cartas": 5, "eliminado": false},
    {"id": 3, "nombre": "Cleo", "nivel": "facil", "cartas": 4, "eliminado": false}
  ],
  "mano": ["doctora_violeta", "daga", "cocina", "piscina", "tijeras"],
  "historial": [
    {"n": 1, "tipo": "sugerencia", "quien": 2,
     "cartas": ["chef_canela", "veneno", "jardin"],
     "respuestas": [{"jugador": 3, "resultado": "no_pudo"}, {"jugador": 1, "resultado": "refuto"}],
     "carta_vista": null},
    {"n": 2, "tipo": "acusacion", "quien": 3,
     "cartas": ["senora_coral", "cuerda", "gimnasio"], "resultado": "falla"}
  ],
  "pendiente": {"tipo": "accion"},
  "libreta": [
    {"carta": "chef_canela", "tipo": "sospechoso", "estado": "descartada", "probabilidad": 0.0},
    {"carta": "veneno", "tipo": "arma", "estado": "dudosa", "probabilidad": 18.4}
  ],
  "fin": null
}
```

| Campo | Valores |
|---|---|
| `modo` | `jugar` o `espectar` (demo: la IA juega por el jugador 1) |
| `estado` | `jugando` (juega una IA), `esperando` (te toca: mira `pendiente`) o `fin` |
| `pendiente` | `null`; `{"tipo": "accion"}` (sugerir o acusar); o `{"tipo": "carta", "sugerencia": {"quien": 2, "cartas": [...]}, "candidatas": [...]}` (tienes que refutar) |
| `historial[].carta_vista` | Solo en tus sugerencias, y solo si alguien refutó: `{"jugador": 3, "carta": "daga"}`. En las de los demás, siempre `null` |
| `libreta[].estado` | `descartada`, `dudosa` o `sobre` (lo que dice `deducir/2`) |
| `libreta[].probabilidad` | Porcentaje de estar en el sobre (`probabilidades/2`); solo se recalcula cuando te toca |
| `fin` | `null` o `{"ganador": 3, "motivo": "acierta", "sobre": [...], "eliminados": [...]}`. Si pierdes, `ganador` es `null` y `motivo` es `"eliminado"` |

`nivel` es `facil`, `media` o `dificil` para las IAs, y `null` para ti. La página compone los textos ("Beto refutó") a partir de estos datos.

**Qué no se cuenta nunca.** El sobre (hasta el `fin`), las manos de los demás, qué carta enseñó cada uno a otro jugador, y el conocimiento de las IAs. Es lo que ya garantiza el protocolo: la página recibe lo mismo que recibiría un jugador por la terminal.

**La libreta es opcional.** Con `"asistente": false` el campo `libreta` es `null` y no se calcula nada. Con `true` (por defecto) se rellena con el conocimiento que el jugador `web` va acumulando con los mismos eventos que ve, usando el mismo motor que la IA media.

**Errores.** `{"error": "codigo", "mensaje": "texto"}` con estos códigos: `partida_no_existe` (404), `rivales_invalidos` (400), `nivel_invalido` (400), `no_esperas_accion` (409), `accion_invalida` (400), `carta_invalida` (400).

**Los nombres de las IAs** (Beto, Cleo...) los pone el servidor. El nombre del humano viene en `nombre`: se recorta a 20 caracteres y, si viene vacío, es "Detective".

## §4 La IA

**Conocimiento.** Cada carta tiene un dueño desconocido: `0` es el sobre y `1..N` son los jugadores. Las observaciones se convierten en restricciones:

| Observación | Restricción |
|---|---|
| Tengo estas cartas | `Dueño #= Yo` |
| Me enseñaron la carta C | `Dueño(C) #= J` |
| J refutó una sugerencia ajena | `Dueño(A) #= J #\/ Dueño(B) #= J #\/ Dueño(C) #= J` |
| J no pudo refutar | `Dueño #\= J` para las tres cartas |
| Reglas del juego | Una carta de cada tipo en el sobre; cada jugador tiene un número fijo de cartas |

**Niveles.**

| Nivel | Comportamiento |
|---|---|
| Fácil | Sugiere al azar entre las cartas que no ha visto, solo recuerda las que le enseñan y acusa cuando le queda una sola de cada tipo |
| Medio | Convierte en restricciones lo que ve (sugerencias de todos, quién no pudo refutar, cartas que le enseñan y acusaciones fallidas), sugiere entre las cartas que aún pueden estar en el sobre y acusa solo cuando `solucion_segura/2` lo demuestra. Al refutar repite la carta que ya enseñó a ese jugador, para no regalar información |
| Difícil | Además elige la sugerencia que más reduce la incertidumbre (ganancia de información) |

**Riesgo conocido.** Con 21 cartas no se pueden enumerar todos los mundos posibles. Para saber qué cartas *pueden* estar en el sobre basta con comprobar, carta por carta, si existe al menos un mundo coherente. Las probabilidades se aproximan por muestreo (F1·04, F1·05).

## §5 Fases

| Fase | Semana | Hecho cuando |
|---|---|---|
| **F0 — Preparación** | antes del 26 oct | Repo, prototipo del motor de deducción y herramientas del repo |
| **F1 — El modelo del juego** | 26 oct – 1 nov | Hay reparto aleatorio y la deducción funciona con el mazo completo y N jugadores, con tests |
| **F2 — Partida en consola** | 2 – 8 nov | Se juega una partida completa en la terminal contra IAs fácil y media. **Versión mínima entregable** |
| **F3 — Interfaz web e IA difícil** | 9 – 15 nov | Se juega en el navegador contra IAs de distinto nivel (fácil, media y difícil), con una libreta asistida por el motor |
| **F4 — Explicación, torneo y entrega** | 16 – 22 nov | La IA explica sus deducciones, hay estadísticas del torneo entre IAs, informe y demo listos |

**Regla principal:** al final de F2 tiene que existir un juego completo en consola. Todo lo posterior es mejora.

Estado de la F2: la partida completa en consola **ya existe** (`swipl src/jugar.pl`).

## §6 Conceptos del curso

| Conferencia | Concepto | Dónde |
|---|---|---|
| Conf. 1–2 | Hechos, reglas, unificación | `juego.pl` |
| Conf. 3 | Resolución SLD, backtracking | Búsqueda de mundos posibles |
| Conf. 4 | Corte y negación | "No pudo refutar", control de turnos |
| Conf. 5 | Aritmética | Probabilidades y ganancia de información |
| Conf. 6 | Metaprogramación | `findall`/`aggregate_all`, estado con `assert`, metaintérprete |
| Extra | CLP(FD) | Todo `deduccion.pl` |
