# Sherlog 🔍

Un juego de deducción al estilo Clue con oponentes de IA que razonan en Prolog.

Proyecto final de la asignatura **Programación Declarativa**.

## La idea

Cada partida reparte las cartas al azar entre los jugadores y deja tres en un sobre: un sospechoso, un arma y un lugar. Gana quien descubra primero qué hay en el sobre.

Los oponentes son una IA escrita en Prolog. Cada jugada (quién mostró una carta, quién no pudo refutar una sugerencia) se convierte en una **restricción lógica** y Prolog deduce solo qué cartas pueden estar en el sobre. No hay tablas de posibilidades programadas a mano: se describe **qué se sabe** y el motor de restricciones (CLP(FD)) saca las conclusiones.

## Estado

🚧 En desarrollo. **Ya se puede jugar una partida completa por la terminal** contra IAs de cuatro niveles y en el navegador. Falta la explicación de las deducciones.

## Requisitos

- [SWI-Prolog](https://www.swi-prolog.org/) 9 o superior

## Jugar

```bash
swipl src/jugar.pl
```

Juegas tú (el jugador 1) contra tres IAs: una media y dos fáciles. Escribe el número de la opción que quieras; con Ctrl-D abandonas.

Puedes elegir los rivales, de 2 a 4, entre `azar`, `facil`, `media` y `dificil`:

```bash
swipl src/jugar.pl media media facil
```

En tu turno puedes **sugerir** (preguntar a los demás si tienen alguna de tres cartas), **acusar** (decir cuál es el sobre: si te equivocas pierdes y la partida termina) o ver el historial. Verás todo lo que hacen los demás, y la carta que te enseñan cuando sugieres. Gana quien acusa bien o el último que queda sin eliminar. Las IAs que se equivocan al acusar quedan eliminadas, pero siguen refutando.

Un fragmento de partida:

```
== Tu turno ==
Tus cartas: Doctora Violeta, Señorita Perla, Veneno, Sala de video y Bodega.
¿Qué quieres hacer?
  1) Sugerir (preguntar a los demás)
  2) Acusar (decir cuál es el sobre)
  3) Ver el historial
> 1
...
Sugieres: Chef Canela, Trofeo y Biblioteca.
  El jugador 2 no pudo refutar.
  El jugador 3 refutó.
  El jugador 3 te enseña: Biblioteca.
```

## Jugar en el navegador

```bash
swipl src/servir.pl
```

Abre http://localhost:8080. En la pantalla de inicio eliges tu nombre, de 2 a 4 rivales y **el nivel de cada uno** (por ejemplo, una difícil y dos fáciles). El servidor sirve la página de `web/` y la API JSON descrita en `PLAN.md` (§3, "La API web"). Cada partida corre en su propio hilo. Con `swipl src/servir.pl 9000` usas otro puerto. Por defecto solo se atiende a tu ordenador; con `swipl src/servir.pl 8080 abierto` también a tu red local.

La **libreta** del detective se rellena sola con lo que deduce el motor (descartadas, cartas seguras y el % de cada carta); se puede apagar al crear la partida. Marcando *Modo demo* juega la IA en tu lugar y ves su libreta pensar.

## Probar la demo

```bash
swipl src/demo.pl
```

Una partida de 21 cartas y 4 jugadores, vista por la IA del jugador 1 (fragmento de la salida):

```
Soy la IA del jugador 1. Mis cartas: Chef Canela, Daga, Biblioteca, Cocina y Piscina.
  En el sobre: [] · descartadas: 5 · dudosas: 16
...
Turno 5: Sugiero Señora Coral, Cuerda, Biblioteca (la biblioteca es mía). Nadie puede refutar.
  En el sobre: [Señora Coral,Cuerda] · descartadas: 14 · dudosas: 5
...
Turno 7: Sugiero Chef Canela, Daga, Gimnasio (las dos primeras son mías). Nadie puede refutar.
  En el sobre: [Señora Coral,Cuerda,Gimnasio] · descartadas: 18 · dudosas: 0

La IA acusa: fue Señora Coral, con Cuerda, en Gimnasio.
```

La IA dedujo la solución sin haber visto esas cartas, solo a partir de quién refutó y quién no.

## Tests

```bash
swipl -q -g run_tests -t halt tests/todos.pl
```

Ejecuta los 522 tests (`tests/test_juego.pl`, `tests/test_deduccion.pl`, `tests/test_consola.pl`, `tests/test_ia.pl`, `tests/test_jugador.pl`, `tests/test_turnos.pl`, `tests/test_sherlog.pl` y `tests/test_servidor.pl`, con [plunit](https://www.swi-prolog.org/pldoc/man?section=plunit)). Muestra el progreso, marca con `FAILED` los que fallen y termina con código 0 si todos pasan o con 1 si alguno falla (se comprueba con `echo $status` en fish, o `echo $?` en bash). Tarda unos dos minutos (los tests de probabilidades y las partidas completas con la IA media son los más lentos). Los de la consola no usan el teclado: leen de un texto y escriben en otro.

Para ejecutar solo un archivo:

```bash
swipl -q -g run_tests -t halt tests/test_deduccion.pl
```

### La IA difícil contra la media

```bash
swipl tests/dificil_vs_media.pl
```

Juega 50 partidas de tres jugadores (una difícil y dos medias, cambiando el asiento de la difícil) y cuenta cuántas gana. Si todos jugaran igual, cada uno ganaría el 33 %. Comprueba también que la difícil nunca queda eliminada y que ninguna decisión tarda 2 s. Tarda unos dos minutos; acepta el número de partidas y una semilla: `swipl tests/dificil_vs_media.pl 20 7`.

### Torneo entre niveles

```bash
swipl tests/torneo.pl
```

Juega las 20 combinaciones posibles de tres niveles (`azar`, `facil`, `media`, `dificil`), 100 partidas cada una, con los asientos rotando. Mide victorias, jugadores eliminados por acusar mal y turnos por partida, y escribe `resultados/torneo.csv`, `resultados/torneo.md` y `resultados/torneo_tiempos.csv`. Usa todos los hilos del ordenador (en 12 hilos tarda unos 12 minutos). Con la misma semilla da exactamente la misma tabla, en serie o en paralelo (los tiempos van en un archivo aparte porque dependen de la máquina). Acepta partidas, semilla, hilos (o `serie`) y carpeta de salida: `swipl tests/torneo.pl 20 7 4 /tmp/res`.

Resultado con la semilla 2026: la difícil gana 1,64 veces lo que le tocaría, la media 1,56, la fácil 0,60 y el azar 0,21. La difícil contra dos medias gana el 46 % de las partidas (el 33 % sería jugar igual); la diferencia con la media es pequeña.

### Partidas largas

```bash
swipl tests/partidas_largas.pl
```

Juega **100 partidas completas solo entre IAs**, con 3, 4 y 5 jugadores y distintas mezclas de niveles, y comprueba que ninguna da error ni algo incoherente: que hay un ganador que no está eliminado, que quien gana acertando coincide con el sobre real, que la IA media y la fácil no se eliminan nunca, que el historial solo tiene eventos públicos, que los turnos van en orden y que la IA media nunca descarta el sobre real. Al final muestra cuántas partidas gana cada nivel (la media gana a la fácil y a la de azar). Tarda unos 20 segundos y termina con código 0 si todo está bien. Acepta una semilla: `swipl tests/partidas_largas.pl 7`.

No forma parte de `todos.pl` porque tarda más.

## Plan

- [x] Motor de deducción con restricciones
- [x] Partida completa en consola: turnos, sugerencias, refutaciones y acusación
- [x] Niveles de IA: fácil, medio (deducción) y difícil (ganancia de información)
- [ ] Explicación de por qué la IA acusa (metaintérprete)
- [ ] Interfaz web con la libreta de detective de la IA
- [ ] Torneo entre niveles de IA

## Conceptos de programación declarativa

| Parte | Concepto |
|---|---|
| Reglas del juego y reparto | Hechos, reglas y restricciones |
| Conocimiento de la IA | Restricciones de dominio finito (CLP(FD)) |
| "No pudo refutar" | Negación |
| Probabilidad de cada carta | Backtracking y `findall` sobre los mundos posibles |
| Estrategia de la IA | Aritmética y ganancia de información |
| "¿Por qué acusó la IA?" | Metaprogramación (metaintérprete) |
