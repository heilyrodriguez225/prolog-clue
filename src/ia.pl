/*  Sherlog: el pensamiento de cada IA.

    Aquí vive lo que decide cada nivel de IA, sobre datos puros (listas
    de cartas, no jugadores). jugador.pl conecta estas decisiones con el
    protocolo de la partida.

    IA fácil: su memoria son las cartas que ha visto (las suyas y las que
    le han enseñado). Sabe que ninguna de ellas está en el sobre.

    IA difícil: sabe lo mismo que la media, pero en vez de preguntar al azar
    entre las cartas posibles pregunta lo que más reduce su incertidumbre
    sobre el sobre (ganancia de información, ver dificil_accion/3).

    IA media: su memoria es un conocimiento de deduccion.pl, con
    restricciones CLP(FD). Convierte en restricciones todo lo que ve en la
    mesa, también las sugerencias de los demás, y deduce qué cartas pueden
    estar en el sobre.

        juego.pl  <-  deduccion.pl  <-  ia.pl  <-  jugador.pl  <-  turnos.pl
*/

:- module(ia,
          [ cartas_sin_ver/3,
            facil_recordar/3,
            facil_sugerencia/2,
            facil_accion/2,
            media_observar/3,
            media_accion/2,
            media_carta_a_mostrar/5,
            dificil_accion/2,
            dificil_accion/3,
            entropia_esperada/5
          ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(random)).
:- use_module(library(error)).
:- use_module(library(pairs)).
:- use_module(library(option)).
:- use_module(library(clpfd), [fd_sup/2]).
:- use_module(juego, [carta/2]).
:- use_module(deduccion).

%!  cartas_sin_ver(+Tipo, +Vistas, -Cartas) is det.
%
%   Cartas son las cartas del Tipo (sospechoso, arma o lugar) que no
%   están en Vistas: las que aún podrían estar en el sobre.

cartas_sin_ver(Tipo, Vistas, Cartas) :-
    findall(C,
            ( carta(Tipo, C), \+ memberchk(C, Vistas) ),
            Cartas).

%!  facil_recordar(+Evento, +Vistas, -Vistas1) is det.
%
%   La IA fácil solo recuerda las cartas que le enseñan: un evento
%   carta_vista(_, Carta) añade la carta a las vistas, sin repetirla.
%   Cualquier otro evento lo ignora.

facil_recordar(Evento, Vistas, Vistas1) :-
    (   Evento = carta_vista(_, Carta),
        \+ memberchk(Carta, Vistas)
    ->  Vistas1 = [Carta|Vistas]
    ;   Vistas1 = Vistas
    ).

%!  facil_sugerencia(+Vistas, -Sugerencia) is det.
%
%   Sugerencia es sugerir(S, A, L), con un sospechoso, un arma y un lugar
%   elegidos al azar entre los que la IA fácil todavía no ha visto.
%   Sugerir cartas que ya ha visto sería malgastar el turno: sabe que
%   no están en el sobre.

facil_sugerencia(Vistas, sugerir(S, A, L)) :-
    una_sin_ver(sospechoso, Vistas, S),
    una_sin_ver(arma, Vistas, A),
    una_sin_ver(lugar, Vistas, L).

% Una carta al azar del tipo dado, entre las que no están en Vistas.
% Si no queda ninguna es que las Vistas son imposibles: el sobre tiene
% siempre una carta de cada tipo, que nadie ha podido enseñar.
una_sin_ver(Tipo, Vistas, Carta) :-
    cartas_sin_ver(Tipo, Vistas, Cartas),
    (   Cartas == []
    ->  existence_error(carta_sin_ver, Tipo)
    ;   random_member(Carta, Cartas)
    ).

%!  facil_accion(+Vistas, -Accion) is det.
%
%   Lo que hace la IA fácil en su turno.
%
%       - Si de cada tipo (sospechoso, arma y lugar) le queda UNA sola
%         carta sin ver, esas tres tienen que ser las del sobre: acusa.
%       - Si no, sugiere (facil_sugerencia/2).
%
%   Solo acusa cuando está segura, así que nunca falla. La contrapartida
%   es que necesita ver casi todas las demás cartas antes de acusar; la
%   IA media, que deduce de lo que ocurre en la mesa, llegará antes.

facil_accion(Vistas, Accion) :-
    cartas_sin_ver(sospechoso, Vistas, Sospechosos),
    cartas_sin_ver(arma, Vistas, Armas),
    cartas_sin_ver(lugar, Vistas, Lugares),
    (   Sospechosos = [S], Armas = [A], Lugares = [L]
    ->  Accion = acusar(S, A, L)
    ;   facil_sugerencia(Vistas, Accion)
    ).

%   ---------------------------------------------------------------------
%   IA media

%!  media_observar(+Yo, +Evento, +K) is det.
%
%   La IA media (el jugador Yo, con conocimiento K) ve un Evento. Lo
%   convierte en restricciones y las añade a K, que es el mismo término
%   (las restricciones viven en sus variables).
%
%       sugerencia(Quien, Cartas, Respuestas)
%           no_pudo(J)    J no tiene ninguna de las tres cartas
%           refuto(J)     J tiene al menos una de las tres (no se sabe cuál)
%       carta_vista(J, Carta)
%           J tiene Carta
%       acusacion(_, Cartas, falla)
%           las tres cartas no son, juntas, las del sobre
%
%   Lo que le ocurre a la propia IA no aporta nada nuevo: no necesita
%   enterarse de que ella misma no pudo refutar, y si ella refutó, ya
%   sabe lo que enseñó. Y cuando es ella quien sugiere y alguien refuta,
%   la carta concreta le llega aparte como carta_vista/2, que dice más
%   que el simple "tiene alguna".
%
%   Las restricciones se añaden con maplist y predicados auxiliares,
%   nunca con forall ni con lambdas: forall las desharía al terminar y
%   las lambdas copiarían K, así que se perderían en los dos casos.

media_observar(Yo, Evento, K) :-
    (   Evento = sugerencia(Quien, Cartas, Respuestas)
    ->  maplist(media_respuesta(K, Yo, Quien, Cartas), Respuestas)
    ;   Evento = carta_vista(J, Carta)
    ->  mostro(K, J, Carta)
    ;   Evento = acusacion(_, Cartas, falla)
    ->  acusacion_fallida(K, Cartas)
    ;   true
    ).

media_respuesta(K, Yo, Quien, Cartas, Respuesta) :-
    (   Respuesta = no_pudo(J), J \== Yo
    ->  no_refuto(K, J, Cartas)
    ;   Respuesta = refuto(J), J \== Yo, Quien \== Yo
    ->  refuto(K, J, Cartas)
    ;   true
    ).

%!  media_accion(+K, -Accion) is det.
%
%   Lo que hace la IA media en su turno.
%
%       - Si de cada tipo solo queda UNA carta que pueda estar en el
%         sobre (es lo que comprueba solucion_segura/2), acusa.
%       - Si no, sugiere una carta de cada tipo entre las que todavía
%         pueden estar en el sobre.
%
%   A diferencia de la IA fácil, no necesita haber visto las cartas: le
%   basta con deducir que no pueden estar en el sobre. Y como solo
%   acusa cuando el motor de restricciones lo demuestra, nunca falla.

media_accion(K, Accion) :-
    posibles_de_tipo(K, sospechoso, Sospechosos),
    posibles_de_tipo(K, arma, Armas),
    posibles_de_tipo(K, lugar, Lugares),
    (   Sospechosos = [S], Armas = [A], Lugares = [L]
    ->  Accion = acusar(S, A, L)
    ;   una_de(sospechoso, Sospechosos, S),
        una_de(arma, Armas, A),
        una_de(lugar, Lugares, L),
        Accion = sugerir(S, A, L)
    ).

% Una carta al azar de la lista. Una lista vacía es imposible: el sobre
% tiene siempre una carta de cada tipo.
una_de(Tipo, Cartas, Carta) :-
    (   Cartas == []
    ->  existence_error(carta_posible, Tipo)
    ;   random_member(Carta, Cartas)
    ).

%!  media_carta_a_mostrar(+Mostradas, +Quien, +Candidatas, -Carta, -Mostradas1) is det.
%
%   La IA media tiene que refutar una sugerencia de Quien y tiene las
%   Candidatas. Elige cuál enseñar procurando dar la menor información
%   posible. Mostradas es lo que ya ha enseñado, una lista de Jugador-Carta.
%
%   Cada carta que enseña le dice a quien la ve que no está en el sobre y
%   que la tiene ella. Por eso:
%
%       1. Si ya le enseñó a Quien alguna de las Candidatas, repite esa:
%          no le cuenta nada nuevo.
%       2. Si no, prefiere una que ya haya enseñado a otro jugador: así se
%          descubren menos cartas distintas de su mano.
%       3. Si no hay ninguna, una al azar.
%
%   Mostradas1 recuerda lo que acaba de enseñar, sin repetir entradas.

media_carta_a_mostrar(Mostradas, Quien, Candidatas, Carta, Mostradas1) :-
    (   member(Repetida, Candidatas),
        memberchk(Quien-Repetida, Mostradas)
    ->  Carta = Repetida
    ;   findall(C, ( member(C, Candidatas), memberchk(_-C, Mostradas) ), YaEnseniadas),
        YaEnseniadas = [_|_]
    ->  random_member(Carta, YaEnseniadas)
    ;   random_member(Carta, Candidatas)
    ),
    (   memberchk(Quien-Carta, Mostradas)
    ->  Mostradas1 = Mostradas
    ;   Mostradas1 = [Quien-Carta|Mostradas]
    ).

%   ---------------------------------------------------------------------
%   IA difícil

%!  dificil_accion(+K, -Accion) is det.
%!  dificil_accion(+K, +Opciones, -Accion) is det.
%
%   Accion es acusar(S, A, L) cuando la solución es segura (igual que la
%   media: nunca acusa mal) y, si no, la sugerencia que más información
%   promete.
%
%   Para decidir, mira mundos posibles (todos si quedan pocos; si no una
%   muestra, ver mundos_posibles/4). Para cada sugerencia candidata y
%   cada mundo calcula qué ocurriría: quién la refutaría y qué carta
%   enseñaría. Agrupa los mundos por ese resultado y mide cuánta
%   incertidumbre sobre el sobre queda en cada grupo (entropia_esperada/5).
%   Elige la sugerencia con la incertidumbre esperada menor.
%
%   Opciones: muestras(N) mundos a muestrear (200), max_candidatas(N)
%   sugerencias a evaluar como mucho (60) y con_mano(Bool) para incluir
%   también cartas de su mano como candidatas (false).

dificil_accion(K, Accion) :-
    dificil_accion(K, [], Accion).

dificil_accion(K, Opciones, Accion) :-
    (   solucion_segura(K, sobre(S, A, L))
    ->  Accion = acusar(S, A, L)
    ;   catch(mejor_sugerencia(K, Opciones, Accion), error(Error, _), avisar_y_fallar(Error))
    ->  true
    ;   media_accion(K, Accion)       % sin mundos que mirar: la media
    ).

% Si la difícil falla de verdad, que no sea en silencio: se avisa y juega como la media.
avisar_y_fallar(Error) :-
    print_message(warning, format("IA difícil: ~p. Juega como la media esta vez.", [Error])),
    fail.

mejor_sugerencia(K, Opciones, sugerir(S, A, L)) :-
    option(muestras(Muestras), Opciones, 200),
    option(max_candidatas(Max), Opciones, 150),
    option(con_mano(ConMano), Opciones, true),
    K = conocimiento(Yo, P),
    candidatas(K, ConMano, Max, Candidatas),
    mundos_posibles(K, Muestras, Cartas, Mundos),
    numero_de_jugadores(P, N),
    orden_de_consulta(Yo, N, Orden),
    maplist(mundo_con_sobre(Cartas), Mundos, Datos),
    findall(Puntos-Candidata,
            ( member(Candidata, Candidatas),
              entropia_esperada(Candidata, Cartas, Orden, Datos, Puntos) ),
            Evaluadas),
    keysort(Evaluadas, [_-sugerencia(S, A, L)|_]).

% Las sugerencias que se evalúan: de cada tipo, las cartas que aún pueden
% estar en el sobre (y, si se pide, las de su mano). Si salen demasiadas,
% una muestra al azar: el orden aleatorio también desempata.
candidatas(K, ConMano, Max, Candidatas) :-
    K = conocimiento(Yo, P),
    findall(T-Cs, ( member(T, [sospechoso, arma, lugar]),
                    posibles_de_tipo(K, T, Posibles),
                    cartas_a_probar(ConMano, Yo, P, T, Posibles, Cs) ),
            [sospechoso-Ss, arma-As, lugar-Ls]),
    findall(sugerencia(S, A, L), ( member(S, Ss), member(A, As), member(L, Ls) ), Todas),
    random_permutation(Todas, Mezcladas),
    length(Mezcladas, Cuantas),
    (   Cuantas > Max
    ->  length(Candidatas, Max), append(Candidatas, _, Mezcladas)
    ;   Candidatas = Mezcladas
    ).

cartas_a_probar(false, _, _, _, Posibles, Posibles).
cartas_a_probar(true, Yo, P, Tipo, Posibles, Cartas) :-
    findall(C, ( carta(Tipo, C), memberchk(C-D, P), D == Yo ), Mias),
    append(Posibles, Mias, Cartas0),
    sort(Cartas0, Cartas).

% Los jugadores son los números que pueden ser dueños de una carta: el
% mayor es el último jugador.
numero_de_jugadores(P, N) :-
    pairs_values(P, Ds),
    maplist(fd_sup, Ds, Sups),
    max_list(Sups, N).

% A quién se le pregunta, por orden: los demás jugadores a partir del siguiente.
orden_de_consulta(Yo, N, Orden) :-
    findall(J, ( between(1, N, Paso), J is (Yo - 1 + Paso) mod N + 1, J =\= Yo ), Orden).

% Un mundo junto con las tres cartas que tiene el sobre, una de cada tipo.
mundo_con_sobre(Cartas, Mundo, mundo(Mundo, [S, A, L])) :-
    cartas_del_sobre(sospechoso, Cartas, Mundo, S),
    cartas_del_sobre(arma, Cartas, Mundo, A),
    cartas_del_sobre(lugar, Cartas, Mundo, L).

cartas_del_sobre(Tipo, Cartas, Mundo, Carta) :-
    nth1(I, Mundo, 0),
    nth1(I, Cartas, Carta),
    carta(Tipo, Carta),
    !.

%!  entropia_esperada(+Sugerencia, +Cartas, +Orden, +Datos, -Puntos) is det.
%
%   Puntos es la incertidumbre (en bits) que se espera que quede sobre el
%   sobre tras hacer la Sugerencia, si los Datos (mundos posibles) son
%   representativos: menos es mejor. Es la suma de la entropía de cada
%   tipo (sospechoso, arma, lugar) dentro de cada grupo de mundos que
%   darían la misma respuesta, ponderada por el tamaño del grupo.
%
%   La respuesta es quién refuta y qué carta enseña. Si quien refuta
%   tiene varias de las tres, cada una es igual de probable.

entropia_esperada(sugerencia(S, A, L), Cartas, Orden, Datos, Puntos) :-
    once(nth1(IS, Cartas, S)), once(nth1(IA, Cartas, A)), once(nth1(IL, Cartas, L)),
    maplist(respuestas_del_mundo([S-IS, A-IA, L-IL], Orden), Datos, Listas),
    append(Listas, Entradas),
    keysort(Entradas, Ordenadas),
    group_pairs_by_key(Ordenadas, Grupos),
    maplist(incertidumbre_del_grupo, Grupos, Pesos),
    sum_list(Pesos, Suma),
    length(Datos, NMundos),
    Puntos is Suma / NMundos.

% Lo que respondería cada jugador en un mundo, como Respuesta-Peso+Sobre.
respuestas_del_mundo(Tuyas, Orden, mundo(Mundo, Sobre), Entradas) :-
    (   member(J, Orden),
        findall(C, ( member(C-I, Tuyas), nth1(I, Mundo, J) ), Tiene),
        Tiene = [_|_]
    ->  length(Tiene, K),
        Peso is 1.0 / K,
        findall(J-C-(Peso-Sobre), member(C, Tiene), Entradas)
    ;   Entradas = [nadie-(1.0-Sobre)]
    ).

% Un grupo de mundos con la misma respuesta: su peso total por la
% incertidumbre sobre el sobre que queda dentro de él.
incertidumbre_del_grupo(_-Miembros, Valor) :-
    findall(P, member(P-_, Miembros), Pesos),
    sum_list(Pesos, Total),
    findall(Hs,
            ( member(Pos, [1, 2, 3]),
              findall(Carta-P, ( member(P-Sobre, Miembros), nth1(Pos, Sobre, Carta) ), Pares),
              entropia(Pares, Total, Hs) ),
            [H1, H2, H3]),
    Valor is Total * (H1 + H2 + H3).

% Entropía (en bits) de una distribución dada por pesos por carta.
entropia(Pares, Total, H) :-
    keysort(Pares, Ordenados),
    group_pairs_by_key(Ordenados, Grupos),
    foldl(suma_de_entropia(Total), Grupos, 0.0, H).

suma_de_entropia(Total, _-Pesos, H0, H) :-
    sum_list(Pesos, W),
    Pr is W / Total,
    H is H0 - Pr * log(Pr) / log(2).
