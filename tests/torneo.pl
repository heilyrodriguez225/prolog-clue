/*  Sherlog: el torneo entre niveles de IA.

    Mide qué nivel juega mejor. No forma parte de tests/todos.pl porque
    tarda minutos.

    Uso, desde la raíz del proyecto:

        swipl tests/torneo.pl                   100 partidas por combinación, semilla 2026
        swipl tests/torneo.pl 20 7              20 partidas, semilla 7
        swipl tests/torneo.pl 20 7 serie        sin paralelismo (un solo hilo)
        swipl tests/torneo.pl 20 7 4            con 4 hilos
        swipl tests/torneo.pl 20 7 4 /tmp/res   y los resultados en otra carpeta

    Qué juega: todas las combinaciones de 3 niveles (azar, facil, media y
    dificil, con repetición): son 20. En cada combinación se juegan N
    partidas y el reparto de asientos rota, así que cada nivel se sienta N/3
    veces en cada asiento y el orden de turno no ayuda a nadie.

    Reproducible: cada partida tiene su propia semilla, que sale de la
    semilla base, la combinación y el número de partida. No depende de en
    qué hilo se juegue ni de en qué orden terminen, así que con la misma
    semilla da la misma tabla en serie y en paralelo.

    Escribe, en resultados/ (o en la carpeta del cuarto argumento):

        torneo.csv           una fila por combinación y nivel
        torneo.md            la misma tabla, más un resumen por nivel
        torneo_tiempos.csv   segundos por partida; NO es reproducible
                             (depende de la máquina), por eso va aparte

    Termina con código 0 si todas las partidas acabaron y con 1 si alguna
    dio error.
*/

:- use_module(library(main)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(library(thread)).
:- use_module(library(random)).
:- use_module(library(filesex)).
:- use_module('../src/turnos').

:- initialization(main, main).

niveles([azar, facil, media, dificil]).

main(Argumentos) :-
    argumentos(Argumentos, N, Semilla, Hilos, Carpeta),
    findall(C, combinacion(C), Combinaciones),
    length(Combinaciones, NC),
    format("Sherlog: torneo, ~w combinaciones x ~w partidas (semilla ~w, ~w hilo(s))~n",
           [NC, N, Semilla, Hilos]),
    findall(partida(Ic, C, I),
            ( nth1(Ic, Combinaciones, C), between(1, N, I) ),
            Partidas),
    findall(jugar_una(Semilla, P, R), member(P, Partidas), Tareas),
    get_time(T0),
    concurrent(Hilos, Tareas, []),
    get_time(T1),
    Total is T1 - T0,
    findall(R, member(jugar_una(_, _, R), Tareas), Resultados),
    format("Terminado en ~1f s~n", [Total]),
    make_directory_path(Carpeta),
    escribir_csv(Combinaciones, Resultados, Carpeta),
    escribir_tiempos(Combinaciones, Resultados, Carpeta),
    escribir_markdown(Combinaciones, Resultados, N, Semilla, Carpeta),
    aggregate_all(count, member(error(_), Resultados), Errores),
    format("Partidas con error: ~w~n", [Errores]),
    (   Errores =:= 0 -> halt(0) ; halt(1) ).

argumentos(Args, N, Semilla, Hilos, Carpeta) :-
    (   Args = [A|_] -> atom_number(A, N) ; N = 100 ),
    (   Args = [_, B|_] -> atom_number(B, Semilla) ; Semilla = 2026 ),
    (   Args = [_, _, H|_]
    ->  (   H == serie -> Hilos = 1 ; atom_number(H, Hilos) )
    ;   current_prolog_flag(cpu_count, Hilos0), Hilos is max(1, Hilos0)
    ),
    (   Args = [_, _, _, D|_] -> Carpeta = D ; Carpeta = resultados ).

% Los multiconjuntos de 3 niveles, siempre en el mismo orden.
combinacion([A, B, C]) :-
    niveles(Ns),
    nth0(I, Ns, A), nth0(J, Ns, B), J >= I,
    nth0(K, Ns, C), K >= J.

% ---------------------------------------------------------------------------
% Una partida
% ---------------------------------------------------------------------------

%   El resultado es r(Ic, Tipos, Ganador, Motivo, Eliminados, Turnos, Segundos)
%   con Tipos la lista de niveles por asiento, o error(Causa).

jugar_una(Semilla, partida(Ic, Combinacion, I), Resultado) :-
    Semilla1 is (Semilla * 1000003 + Ic * 10007 + I) mod 2147483647,
    set_random(seed(Semilla1)),             % el generador es de cada hilo
    rotar(Combinacion, I, Tipos),
    get_time(T0),
    catch(( iniciar_partida(Tipos, Partida, Jugadores),
            jugar(Partida, Jugadores,
                  fin(Ganador, Motivo, partida(_, _, _, Eliminados, Historial), _)),
            length(Historial, Turnos),
            get_time(T1),
            Segundos is T1 - T0,
            Resultado = r(Ic, Tipos, Ganador, Motivo, Eliminados, Turnos, Segundos)
          ),
          Causa,
          ( print_message(error, Causa), Resultado = error(Causa) )).

% Rota la combinación para que cada nivel pase por todos los asientos.
rotar(Lista, I, Rotada) :-
    length(Lista, L),
    K is (I - 1) mod L,
    length(Prefijo, K),
    append(Prefijo, Resto, Lista),
    append(Resto, Prefijo, Rotada).

% ---------------------------------------------------------------------------
% Estadísticas
% ---------------------------------------------------------------------------

% Para un nivel de una combinación:
%   fila(Combinacion, Nivel, Asientos, Partidas, Victorias, Eliminados, TurnosSiGana)
filas(Combinaciones, Resultados, Filas) :-
    findall(fila(C, Nivel, K, N, V, E, TS),
            ( nth1(Ic, Combinaciones, C),
              sort(C, Distintos),
              member(Nivel, Distintos),
              include(=(Nivel), C, Iguales), length(Iguales, K),
              findall(R, ( member(R, Resultados), R = r(Ic, _, _, _, _, _, _) ), Rs),
              length(Rs, N),
              findall(T, ( member(r(Ic, Tipos, G, _, _, T, _), Rs),
                           nth1(G, Tipos, Nivel) ), TsGana),
              length(TsGana, V),
              aggregate_all(sum(Ne),
                            ( member(r(Ic, Tipos2, _, _, Elim, _, _), Rs),
                              findall(A, ( member(A, Elim), nth1(A, Tipos2, Nivel) ), As),
                              length(As, Ne) ),
                            E),
              media(TsGana, TS)
            ),
            Filas).

media([], nan) :- !.
media(L, M) :- sum_list(L, S), length(L, N), M is S / N.

pct(_, 0, 0.0) :- !.
pct(Parte, Total, P) :- P is 100.0 * Parte / Total.

nombre_combinacion(C, Nombre) :- atomic_list_concat(C, '+', Nombre).

% Turnos medios de toda la partida, por combinación.
turnos_medios(Ic, Resultados, M) :-
    findall(T, member(r(Ic, _, _, _, _, T, _), Resultados), Ts),
    media(Ts, M).

num(nan, "-") :- !.
num(X, S) :- format(string(S), "~1f", [X]).

% ---------------------------------------------------------------------------
% Salidas
% ---------------------------------------------------------------------------

escribir_csv(Combinaciones, Resultados, Carpeta) :-
    filas(Combinaciones, Resultados, Filas),
    directory_file_path(Carpeta, 'torneo.csv', Ruta),
    setup_call_cleanup(
        open(Ruta, write, S),
        ( format(S, "combinacion,nivel,asientos,partidas,victorias,pct_victorias,pct_esperado,pct_eliminados,turnos_partida,turnos_si_gana~n", []),
          forall(member(fila(C, Nivel, K, N, V, E, TS), Filas),
                 ( nombre_combinacion(C, Nom),
                   nth1(Ic, Combinaciones, C),
                   turnos_medios(Ic, Resultados, TP),
                   pct(V, N, PV), PE is 100.0 * K / 3,
                   pct(E, N * K, PEl),
                   num(TP, TPs), num(TS, TSs),
                   format(S, "~w,~w,~w,~w,~w,~1f,~1f,~1f,~s,~s~n",
                          [Nom, Nivel, K, N, V, PV, PE, PEl, TPs, TSs]) ))
        ),
        close(S)),
    format("Escrito ~w~n", [Ruta]).

escribir_tiempos(Combinaciones, Resultados, Carpeta) :-
    directory_file_path(Carpeta, 'torneo_tiempos.csv', Ruta),
    setup_call_cleanup(
        open(Ruta, write, S),
        ( format(S, "combinacion,segundos_por_partida~n", []),
          forall(nth1(Ic, Combinaciones, C),
                 ( findall(T, member(r(Ic, _, _, _, _, _, T), Resultados), Ts),
                   media(Ts, M), num(M, Ms), nombre_combinacion(C, Nom),
                   format(S, "~w,~s~n", [Nom, Ms]) ))
        ),
        close(S)),
    format("Escrito ~w~n", [Ruta]).

escribir_markdown(Combinaciones, Resultados, N, Semilla, Carpeta) :-
    filas(Combinaciones, Resultados, Filas),
    directory_file_path(Carpeta, 'torneo.md', Ruta),
    setup_call_cleanup(
        open(Ruta, write, S),
        ( format(S, "# Torneo entre niveles de IA~n~n", []),
          format(S, "Partidas de 3 jugadores, ~w por combinación, semilla ~w. Los asientos rotan, así que cada nivel se sienta igual de veces en cada asiento.~n~n", [N, Semilla]),
          resumen(S, Filas, Resultados),
          detalle(S, Combinaciones, Resultados, Filas)
        ),
        close(S)),
    format("Escrito ~w~n", [Ruta]).

% Por nivel, sobre todas las partidas: cuántas gana frente a las que
% ganaría si todos jugaran igual (1/3 por asiento ocupado).
resumen(S, Filas, Resultados) :-
    length(Resultados, Total),
    format(S, "## Resumen por nivel (~w partidas)~n~n", [Total]),
    format(S, "| Nivel | Victorias | Esperadas si todos jugaran igual | Ventaja | Eliminado por acusar mal |~n", []),
    format(S, "|---|---:|---:|---:|---:|~n", []),
    niveles(Ns),
    forall(member(Nivel, Ns),
           ( aggregate_all(sum(V), member(fila(_, Nivel, _, _, V, _, _), Filas), Vs),
             aggregate_all(sum(K * Np / 3), member(fila(_, Nivel, K, Np, _, _, _), Filas), Esp),
             aggregate_all(sum(E), member(fila(_, Nivel, _, _, _, E, _), Filas), Es),
             aggregate_all(sum(K * Np), member(fila(_, Nivel, K, Np, _, _, _), Filas), Asientos),
             (   Esp > 0 -> Vent is Vs / Esp ; Vent = 0.0 ),
             pct(Es, Asientos, PEl),
             format(S, "| ~w | ~w | ~1f | ~2fx | ~1f % |~n", [Nivel, Vs, Esp, Vent, PEl]) )),
    format(S, "~n", []).

detalle(S, Combinaciones, Resultados, Filas) :-
    format(S, "## Por combinación~n~n", []),
    format(S, "| Combinación | Nivel | Asientos | Victorias | % victorias | % esperado | Turnos medios de la partida | Turnos medios si gana |~n", []),
    format(S, "|---|---|---:|---:|---:|---:|---:|---:|~n", []),
    forall(member(fila(C, Nivel, K, N, V, _, TS), Filas),
           ( nombre_combinacion(C, Nom),
             nth1(Ic, Combinaciones, C),
             turnos_medios(Ic, Resultados, TP),
             pct(V, N, PV), PE is 100.0 * K / 3,
             num(TP, TPs), num(TS, TSs),
             format(S, "| ~w | ~w | ~w | ~w de ~w | ~1f % | ~1f % | ~s | ~s |~n",
                    [Nom, Nivel, K, V, N, PV, PE, TPs, TSs]) )).
