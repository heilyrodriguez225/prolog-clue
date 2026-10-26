/*  Sherlog: motor de deducción de la IA.

    Cada carta tiene un dueño desconocido, representado como una variable
    de dominio finito:
        0     = el sobre (la solución)
        1..N  = los jugadores

    Cada jugada de la partida añade una restricción, y CLP(FD) propaga
    las consecuencias sin que haya que programar cómo deducir.
*/

:- module(deduccion,
          [ modelo/2,
            tengo/3,
            mostro/3,
            refuto/3,
            no_refuto/3,
            probabilidades/2,
            solucion_segura/2
          ]).

:- use_module(library(clpfd)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(aggregate)).

sospechosos([mostaza, escarlata, prado, blanco]).
armas([cuchillo, cuerda, pistola]).
lugares([cocina, biblioteca, salon]).

%!  modelo(+Reparto, -P) is det.
%
%   Crea el modelo de conocimiento. Reparto indica cuántas cartas tiene
%   cada jugador, por ejemplo [3, 2, 2]. P es una lista Carta-Dueño.
modelo(Reparto, P) :-
    sospechosos(S), armas(A), lugares(L),
    append([S, A, L], Cartas),
    length(Reparto, NJ),
    same_length(Cartas, Ds),
    Ds ins 0..NJ,
    pairs_keys_values(P, Cartas, Ds),
    maplist(uno_en_sobre(P), [S, A, L]),
    numlist(1, NJ, Js),
    pairs_keys_values(Cuentas, Js, Reparto),
    global_cardinality(Ds, [0-3|Cuentas]).

% Exactamente una carta de cada tipo está en el sobre.
uno_en_sobre(P, Tipo) :-
    maplist(en_sobre(P), Tipo, Bs),
    sum(Bs, #=, 1).

dueno(P, C, D)    :- memberchk(C-D, P).
en_sobre(P, C, B) :- dueno(P, C, D), B #<==> (D #= 0).
es_de(P, J, C)    :- dueno(P, C, D), D #= J.
no_es_de(P, J, C) :- dueno(P, C, D), D #\= J.

%   Hechos observados durante la partida.
%   Ojo: usar maplist y no forall, porque forall deshace las restricciones.

tengo(P, J, Cartas)  :- maplist(es_de(P, J), Cartas).
mostro(P, J, Carta)  :- es_de(P, J, Carta).
no_refuto(P, J, Cs)  :- maplist(no_es_de(P, J), Cs).

% El jugador J refutó: tiene AL MENOS una de las tres cartas (no se sabe cuál).
refuto(P, J, [A, B, C]) :-
    dueno(P, A, DA), dueno(P, B, DB), dueno(P, C, DC),
    (DA #= J) #\/ (DB #= J) #\/ (DC #= J).

%!  probabilidades(+P, -Probs) is det.
%
%   Probs es una lista Carta-Porcentaje con la probabilidad de que cada
%   carta esté en el sobre, contando los mundos posibles.
probabilidades(P, Probs) :-
    pairs_values(P, Ds),
    findall(Ds, label(Ds), Mundos),
    length(Mundos, N),
    N > 0,
    findall(C-Pct,
            ( nth1(I, P, C-_),
              aggregate_all(count, (member(M, Mundos), nth1(I, M, 0)), K),
              K > 0,
              Pct is 100.0 * K / N ),
            Probs).

%!  solucion_segura(+P, -Solucion) is semidet.
%
%   Tiene éxito si la solución ya se puede deducir con certeza.
solucion_segura(P, Solucion) :-
    probabilidades(P, Probs),
    findall(C, member(C-100.0, Probs), Solucion),
    length(Solucion, 3).
