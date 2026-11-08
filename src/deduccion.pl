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
            acusacion_fallida/2,
            estado_carta/3,
            puede_estar_en_sobre/2,
            posibles_en_sobre/2,
            posibles_de_tipo/3,
            deducir/2,
            probabilidades/2,
            probabilidades/3,
            probabilidades_exactas/2,
            muestrear/3,
            mundos_posibles/4,
            solucion_segura/2
          ]).

:- use_module(library(clpfd)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(aggregate)).
:- use_module(library(random)).
:- use_module(library(solution_sequences)).
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

%!  acusacion_fallida(+K, +Cartas) is semidet.
%
%   Alguien acusó a Cartas = [S, A, L] y se equivocó: esas tres cartas NO
%   son las del sobre. No se sabe cuál de las tres está mal; solo que no
%   están las tres juntas en el sobre.
acusacion_fallida(conocimiento(_, P), [A, B, C]) :-
    dueno(P, A, DA), dueno(P, B, DB), dueno(P, C, DC),
    (DA #\= 0) #\/ (DB #\= 0) #\/ (DC #\= 0).

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

%!  probabilidades(+K, -Probs) is semidet.
%!  probabilidades(+K, +NMuestras, -Probs) is semidet.
%
%   Probs es una lista Carta-Porcentaje, con las 21 cartas: la
%   probabilidad de que cada una esté en el sobre según el dueño de K.
%   Falla si K es contradictorio (no queda ningún mundo posible).
%
%   Es un método híbrido:
%
%       - si quedan pocos mundos posibles, los enumera todos y el
%         resultado es exacto;
%       - si no (al empezar hay millones), los estima con NMuestras
%         mundos elegidos al azar por muestrear/3.
probabilidades(K, Probs) :-
    muestras_por_defecto(N),
    probabilidades(K, N, Probs).

probabilidades(K, NMuestras, Probs) :-
    limite_exacto(Limite),
    (   mundos_si_pocos(K, Limite, Mundos)
    ->  true
    ;   muestrear(K, NMuestras, Mundos)
    ),
    Mundos = [_|_],
    frecuencias(Mundos, Probs).

%!  probabilidades_exactas(+K, -Probs) is semidet.
%
%   Igual que probabilidades/2, pero enumerando siempre todos los mundos.
%   Solo termina cuando quedan pocos; sirve para comparar y para los tests.
probabilidades_exactas(K, Probs) :-
    findall(Sobre, mundo(K, Sobre), Mundos),
    Mundos = [_|_],
    frecuencias(Mundos, Probs).

% Parámetros del método híbrido.
muestras_por_defecto(250).
limite_exacto(500).
pasos_entre_muestras(10).
pasos_de_calentamiento(100).

% Un mundo posible, dado por las tres cartas que hay en el sobre.
mundo(conocimiento(_, P), Sobre) :-
    pairs_values(P, Ds),
    label(Ds),
    cartas_en_sobre(P, Sobre).

cartas_en_sobre(P, Sobre) :-
    findall(C, member(C-0, P), Sobre).

% Mundos posibles, si hay Limite o menos. Falla si hay más.
mundos_si_pocos(K, Limite, Mundos) :-
    Maximo is Limite + 1,
    findall(S, limit(Maximo, mundo(K, S)), Mundos),
    length(Mundos, N),
    N =< Limite.

% Porcentaje de mundos en los que cada carta está en el sobre.
frecuencias(Mundos, Probs) :-
    length(Mundos, N),
    findall(C-Pct,
            ( carta(_, C),
              aggregate_all(count, (member(M, Mundos), memberchk(C, M)), K),
              Pct is 100.0 * K / N ),
            Probs).

%!  muestrear(+K, +N, -Mundos) is semidet.
%
%   Mundos son N mundos posibles (cada uno, las 3 cartas del sobre)
%   obtenidos con una cadena de Markov (Metropolis-Hastings).
%
%   Se parte de un mundo cualquiera y se va cambiando de mundo
%   intercambiando el dueño de dos cartas. El cambio solo se acepta si
%   el nuevo mundo cumple todas las restricciones de K: se comprueba
%   unificando las variables con él. Como la propuesta es simétrica y
%   solo se rechazan mundos imposibles, a la larga todos los mundos
%   posibles son igual de probables.
muestrear(K, N, Sobres) :-
    muestrear_duenos(K, N, Mundos),
    K = conocimiento(_, P),
    pairs_keys(P, Cartas),
    maplist(sobre_de_mundo(Cartas), Mundos, Sobres).

%!  muestrear_duenos(+K, +N, -Mundos) is semidet.
%
%   Como muestrear/3, pero cada mundo es la lista completa de dueños de
%   las 21 cartas, en el orden de K (0 es el sobre, 1..N los jugadores).
muestrear_duenos(conocimiento(_, P), N, Mundos) :-
    pairs_values(P, Ds),
    pairs_keys(P, Cartas),
    maplist(tipo_de_carta, Cartas, Tipos),
    random_between(1, 1000000, Semilla),
    findall(Ds,
            once(labeling([random_variable(Semilla), random_value(Semilla)], Ds)),
            [Mundo0]),
    pasos_de_calentamiento(Calentamiento),
    avanzar(Calentamiento, Ds, Tipos, Mundo0, Mundo1),
    recoger(N, Ds, Tipos, Mundo1, Mundos).

sobre_de_mundo(Cartas, Mundo, Sobre) :-
    findall(C, (nth1(I, Mundo, 0), nth1(I, Cartas, C)), Sobre).

%!  mundos_posibles(+K, +N, -Cartas, -Mundos) is semidet.
%
%   Mundos posibles según K, cada uno la lista de dueños alineada con
%   Cartas (las 21 cartas, en orden). Si quedan 500 o menos son todos los
%   que hay (exacto); si no, N mundos muestreados. Falla si K es
%   contradictorio.
mundos_posibles(K, N, Cartas, Mundos) :-
    K = conocimiento(_, P),
    pairs_keys(P, Cartas),
    limite_exacto(Limite),
    Maximo is Limite + 1,
    pairs_values(P, Ds),
    findall(Ds, limit(Maximo, (label(Ds))), Todos),
    length(Todos, Cuantos),
    (   Cuantos =< Limite
    ->  Mundos = Todos
    ;   muestrear_duenos(K, N, Mundos)
    ),
    Mundos = [_|_].

tipo_de_carta(Carta, Tipo) :- once(carta(Tipo, Carta)).

recoger(0, _, _, _, []) :- !.
recoger(N, Ds, Tipos, Mundo0, [Mundo|Mundos]) :-
    pasos_entre_muestras(Pasos),
    avanzar(Pasos, Ds, Tipos, Mundo0, Mundo),
    N1 is N - 1,
    recoger(N1, Ds, Tipos, Mundo, Mundos).

% Da Pasos pasos de la cadena, partiendo del mundo Mundo0.
avanzar(0, _, _, Mundo, Mundo) :- !.
avanzar(Pasos, Ds, Tipos, Mundo0, Mundo) :-
    (   maybe
    ->  proponer_cambio_en_sobre(Mundo0, Tipos, I, J)
    ;   proponer_cambio(Mundo0, I, J)
    ),
    (   nonvar(J),
        intercambiar(Mundo0, I, J, Candidato),
        \+ \+ Ds = Candidato          % ¿cumple todas las restricciones?
    ->  Mundo1 = Candidato
    ;   Mundo1 = Mundo0
    ),
    Pasos1 is Pasos - 1,
    avanzar(Pasos1, Ds, Tipos, Mundo1, Mundo).

% Dos cartas con distinto dueño, al azar.
proponer_cambio(Mundo, I, J) :-
    length(Mundo, L),
    random_between(1, L, I),
    nth1(I, Mundo, DuenoI),
    findall(X, (nth1(X, Mundo, D), D =\= DuenoI), Candidatas),
    (   Candidatas = [] -> true ; random_member(J, Candidatas) ).

% Una carta del sobre y otra de su mismo tipo que no está en el sobre.
% Sin estos cambios el sobre casi nunca se movería: un cambio al azar
% pocas veces cae en una carta del sobre y otra de su tipo.
proponer_cambio_en_sobre(Mundo, Tipos, I, J) :-
    findall(X, nth1(X, Mundo, 0), EnSobre),
    random_member(I, EnSobre),
    nth1(I, Tipos, Tipo),
    findall(X, ( nth1(X, Mundo, D), D =\= 0, nth1(X, Tipos, Tipo) ), Candidatas),
    (   Candidatas = [] -> true ; random_member(J, Candidatas) ).

% Mundo con los dueños de las cartas I y J intercambiados.
intercambiar(Mundo, I, J, Candidato) :-
    nth1(I, Mundo, DuenoI),
    nth1(J, Mundo, DuenoJ),
    findall(D,
            ( nth1(X, Mundo, D0),
              (   X =:= I -> D = DuenoJ
              ;   X =:= J -> D = DuenoI
              ;   D = D0 ) ),
            Candidato).

%!  solucion_segura(+K, -Sobre) is semidet.
%
%   Tiene éxito si el dueño de K ya puede deducir con certeza la
%   solución: de cada tipo queda exactamente una carta posible.
%   Sobre es sobre(Sospechoso, Arma, Lugar).
solucion_segura(K, sobre(S, A, L)) :-
    posibles_de_tipo(K, sospechoso, [S]),
    posibles_de_tipo(K, arma, [A]),
    posibles_de_tipo(K, lugar, [L]).
