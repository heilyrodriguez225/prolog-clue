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
            cuentas/2,
            conocimiento_inicial/3,
            mostro/3,
            refuto/3,
            no_refuto/3,
            estado_carta/3,
            puede_estar_en_sobre/2,
            posibles_en_sobre/2,
            deducir/2,
            probabilidades/2,
            solucion_segura/2
          ]).

:- use_module(library(clpfd)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(aggregate)).
:- use_module(juego, [carta/2]).

% Las cartas de un tipo, tomadas del mazo de juego.pl.
cartas_de_tipo(Tipo, Cartas) :-
    findall(C, carta(Tipo, C), Cartas).

%!  modelo(+Reparto, -P) is det.
%
%   Crea el modelo de conocimiento. Reparto indica cuántas cartas tiene
%   cada jugador, por ejemplo [5, 5, 4, 4]. P es una lista Carta-Dueño.
modelo(Reparto, P) :-
    maplist(cartas_de_tipo, [sospechoso, arma, lugar], [S, A, L]),
    append([S, A, L], Cartas),
    length(Reparto, NJ),
    same_length(Cartas, Ds),
    Ds ins 0..NJ,
    pairs_keys_values(P, Cartas, Ds),
    maplist(uno_en_sobre(P), [S, A, L]),
    numlist(1, NJ, Js),
    pairs_keys_values(Cuentas, Js, Reparto),
    global_cardinality(Ds, [0-3|Cuentas]).

%!  cuentas(+Partida, -Cuentas) is det.
%
%   Cuántas cartas tiene cada jugador, en orden: [5, 5, 4, 4]. Es
%   información pública (se ve en la mesa); las cartas en sí, no.
cuentas(partida(_, Manos, _, _, _), Cuentas) :-
    pairs_values(Manos, ListasDeCartas),
    maplist(length, ListasDeCartas, Cuentas).

% Exactamente una carta de cada tipo está en el sobre.
uno_en_sobre(P, Tipo) :-
    maplist(en_sobre(P), Tipo, Bs),
    sum(Bs, #=, 1).

dueno(P, C, D)    :- memberchk(C-D, P).
en_sobre(P, C, B) :- dueno(P, C, D), B #<==> (D #= 0).
es_de(P, J, C)    :- dueno(P, C, D), D #= J.
no_es_de(P, J, C) :- dueno(P, C, D), D #\= J.

%!  conocimiento_inicial(+Yo, +Partida, -K) is det.
%
%   K = conocimiento(Yo, P) es lo que sabe el jugador Yo al empezar: las
%   reglas del juego, cuántas cartas tiene cada uno y su propia mano.
%   Cada IA tiene el suyo, porque cada una ve cosas distintas.
conocimiento_inicial(Yo, Partida, conocimiento(Yo, P)) :-
    cuentas(Partida, Cuentas),
    modelo(Cuentas, P),
    mano(Partida, Yo, Mano),
    tengo(P, Yo, Mano).

mano(partida(_, Manos, _, _, _), J, Mano) :-
    memberchk(J-Mano, Manos).

%   Observaciones durante la partida: cada una añade restricciones al
%   conocimiento K de quien la ve.
%   Ojo: usar maplist y no forall, porque forall deshace las restricciones.

tengo(P, J, Cartas) :- maplist(es_de(P, J), Cartas).

% Al dueño de K, el jugador J le enseñó Carta.
mostro(conocimiento(_, P), J, Carta) :- es_de(P, J, Carta).

% El jugador J no pudo refutar: no tiene ninguna de las tres cartas.
no_refuto(conocimiento(_, P), J, Cs) :- maplist(no_es_de(P, J), Cs).

% El jugador J refutó: tiene AL MENOS una de las tres cartas (no se sabe cuál).
refuto(conocimiento(_, P), J, [A, B, C]) :-
    dueno(P, A, DA), dueno(P, B, DB), dueno(P, C, DC),
    (DA #= J) #\/ (DB #= J) #\/ (DC #= J).

%!  estado_carta(+K, ?Carta, -Estado) is nondet.
%
%   Qué sabe el dueño de K sobre Carta, usando solo la propagación de
%   CLP(FD), sin buscar. Es instantáneo con el mazo completo.
%
%       sobre       el dueño solo puede ser 0: está en el sobre
%       descartada  el dueño no puede ser 0: la tiene algún jugador
%       dudosa      todavía puede estar en el sobre o en un jugador
%
%   Es incompleto: hay deducciones que exigen buscar (ver #7).
estado_carta(conocimiento(_, P), Carta, Estado) :-
    member(Carta-D, P),
    fd_inf(D, Min),
    fd_sup(D, Max),
    (   Max =:= 0 -> Estado = sobre
    ;   Min > 0   -> Estado = descartada
    ;   Estado = dudosa
    ).

%!  puede_estar_en_sobre(+K, +Carta) is semidet.
%
%   Tiene éxito si existe AL MENOS UN mundo coherente con todo lo que
%   sabe el dueño de K en el que Carta está en el sobre. Busca un solo
%   mundo (once/1) en lugar de enumerarlos todos.
%
%   La doble negación \+ \+ comprueba sin dejar rastro: al terminar se
%   deshacen D #= 0 y el etiquetado, y K queda como estaba.
puede_estar_en_sobre(conocimiento(_, P), Carta) :-
    dueno(P, Carta, D),
    pairs_values(P, Ds),
    \+ \+ ( D #= 0, once(labeling([ff], Ds)) ).

%!  posibles_en_sobre(+K, -Cartas) is det.
%
%   Todas las cartas que, según el dueño de K, todavía pueden estar en
%   el sobre.
posibles_en_sobre(K, Cartas) :-
    findall(C,
            ( member(Tipo, [sospechoso, arma, lugar]),
              posibles_de_tipo(K, Tipo, Posibles),
              member(C, Posibles) ),
            Cartas).

%!  deducir(+K, -Estados) is det.
%
%   Estado de cada carta, con búsqueda además de propagación. Estados es
%   una lista Carta-Estado:
%
%       sobre       es la única de su tipo que puede estar en el sobre
%       descartada  no puede estar en el sobre
%       dudosa      puede estar, y hay otras de su tipo que también
%
%   A diferencia de estado_carta/3, es completo: lo que se deduce, sale.
deducir(K, Estados) :-
    findall(C-E,
            ( member(Tipo, [sospechoso, arma, lugar]),
              posibles_de_tipo(K, Tipo, Posibles),
              cartas_de_tipo(Tipo, Cartas),
              member(C, Cartas),
              clasificar(C, Posibles, E) ),
            Estados).

% Las cartas de un tipo que pueden estar en el sobre. Primero se miran
% las que la propagación no descarta, para no buscar en vano.
posibles_de_tipo(K, Tipo, Posibles) :-
    cartas_de_tipo(Tipo, Cartas),
    include(posible(K), Cartas, Posibles).

posible(K, C) :-
    estado_carta(K, C, E),
    E \== descartada,
    puede_estar_en_sobre(K, C).

clasificar(C, Posibles, Estado) :-
    (   \+ memberchk(C, Posibles) -> Estado = descartada
    ;   Posibles = [_]            -> Estado = sobre
    ;   Estado = dudosa
    ).

%!  probabilidades(+K, -Probs) is det.
%
%   Probs es una lista Carta-Porcentaje con la probabilidad de que cada
%   carta esté en el sobre, contando los mundos posibles.
%
%   Solo sirve cuando quedan pocos mundos posibles: al empezar una
%   partida de 21 cartas hay millones y no termina. Se reemplaza en #8.
probabilidades(conocimiento(_, P), Probs) :-
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

%!  solucion_segura(+K, -Sobre) is semidet.
%
%   Tiene éxito si el dueño de K ya puede deducir con certeza la
%   solución: de cada tipo queda exactamente una carta posible.
%   Sobre es sobre(Sospechoso, Arma, Lugar).
solucion_segura(K, sobre(S, A, L)) :-
    posibles_de_tipo(K, sospechoso, [S]),
    posibles_de_tipo(K, arma, [A]),
    posibles_de_tipo(K, lugar, [L]).
