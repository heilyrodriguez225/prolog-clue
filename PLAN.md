# Plan de Sherlog

El *qué* y el *por qué* de cada fase. El *ahora* está en el tablero Scrumban.

## §1 La idea

Sherlog es un juego de deducción al estilo Clue: tú contra 2–4 oponentes de IA que razonan en Prolog. Lo importante del proyecto es **cómo piensa la IA**: cada jugada se convierte en una restricción lógica y el motor CLP(FD) deduce qué cartas pueden estar en el sobre.

Proyecto final de Programación Declarativa: una persona, **un mes** (26 oct – 22 nov 2026), una fase por semana.

## §2 Reglas de Sherlog

Basadas en Clue, simplificadas para que todo el esfuerzo vaya a la parte declarativa.

| Regla | Decisión |
|---|---|
| Mazo | 6 sospechosos, 6 armas, 9 lugares (21 cartas). Los nombres se deciden en F1·01 |
| Sobre | 1 carta de cada tipo, elegida al azar |
| Jugadores | 1 humano + 2–4 IAs (3–5 en total). El resto de cartas se reparte lo más parejo posible |
| Tablero | **No hay tablero ni dados.** En su turno, cada jugador sugiere cualquier lugar |
| Sugerencia | "Fue X con Y en Z". Se pregunta en orden a los siguientes jugadores; el primero que tenga alguna de las tres cartas enseña **una** solo a quien sugirió |
| Lo que ven los demás | Quién refutó y quién no pudo, pero no la carta enseñada |
| Acusación | Si acierta, gana. Si falla, queda eliminado pero sigue refutando |

## §3 Arquitectura

```
src/
  juego.pl        cartas, reparto, estado de la partida y turnos
  deduccion.pl    conocimiento de cada IA como restricciones CLP(FD)
  ia.pl           niveles de IA: fácil, medio y difícil
  explicacion.pl  metaintérprete: por qué la IA sabe lo que sabe
  consola.pl      interfaz de texto
  servidor.pl     API HTTP/JSON (library(http))
web/              página del juego (HTML, CSS, JS)
tests/            tests con plunit
```

La interfaz web no tiene lógica de juego: solo muestra el estado y envía las acciones del jugador. **Todas las reglas y la IA viven en Prolog.**

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
| Fácil | Sugiere al azar y solo recuerda las cartas que le enseñaron |
| Medio | Deduce con todas las restricciones y acusa cuando la solución es segura |
| Difícil | Además elige la sugerencia que más reduce la incertidumbre (ganancia de información) |

**Riesgo conocido.** Con 21 cartas no se pueden enumerar todos los mundos posibles. Para saber qué cartas *pueden* estar en el sobre basta con comprobar, carta por carta, si existe al menos un mundo coherente. Las probabilidades se aproximan por muestreo (F1·04, F1·05).

## §5 Fases

| Fase | Semana | Hecho cuando |
|---|---|---|
| **F0 — Preparación** | antes del 26 oct | Repo, prototipo del motor de deducción y herramientas del repo |
| **F1 — El modelo del juego** | 26 oct – 1 nov | Hay reparto aleatorio y la deducción funciona con el mazo completo y N jugadores, con tests |
| **F2 — Partida en consola** | 2 – 8 nov | Se juega una partida completa en la terminal contra IAs fácil y media. **Versión mínima entregable** |
| **F3 — Interfaz web e IA difícil** | 9 – 15 nov | Se juega en el navegador, con la libreta de detective de la IA y el nivel difícil |
| **F4 — Explicación, torneo y entrega** | 16 – 22 nov | La IA explica sus deducciones, hay estadísticas del torneo entre IAs, informe y demo listos |

**Regla principal:** al final de F2 tiene que existir un juego completo en consola. Todo lo posterior es mejora.

## §6 Conceptos del curso

| Conferencia | Concepto | Dónde |
|---|---|---|
| Conf. 1–2 | Hechos, reglas, unificación | `juego.pl` |
| Conf. 3 | Resolución SLD, backtracking | Búsqueda de mundos posibles |
| Conf. 4 | Corte y negación | "No pudo refutar", control de turnos |
| Conf. 5 | Aritmética | Probabilidades y ganancia de información |
| Conf. 6 | Metaprogramación | `findall`/`aggregate_all`, estado con `assert`, metaintérprete |
| Extra | CLP(FD) | Todo `deduccion.pl` |
