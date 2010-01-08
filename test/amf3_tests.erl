-module(amf3_tests).
-include_lib("eunit/include/eunit.hrl").


-define(assertEncode(Term, AMF),  (AMF == amf3:encode(Term))).
-define(assertDecode(Term, AMF),  ({Term,<<>>} == amf3:decode(AMF))).
-define(assertEncodeDecode(Term), ({Term,<<>>} == amf3:decode(amf3:encode(Term)))).
-define(assertDecodeEncode(AMF),  (AMF == amf3:encode(element(1,amf3:decode(AMF))))).

-define(a(Term, AMF),   ?assert(?assertEncode(Term, AMF) and 
                                ?assertDecode(Term, AMF) and 
                                ?assertEncodeDecode(Term) and 
                                ?assertDecodeEncode(AMF))).
                                
-define(_a(Term, AMF), ?_assert(?assertEncode(Term, AMF) and 
                                ?assertDecode(Term, AMF) and 
                                ?assertEncodeDecode(Term) and 
                                ?assertDecodeEncode(AMF))).



remaining_test() -> ?assertEqual({undefined,<<16#01>>},amf3:decode(<<16#00,16#01>>)).


undefined_test() -> ?a(undefined, <<16#00>>).
null_test() -> ?a(null, <<16#01>>).                            
false_test() -> ?a(false, <<16#02>>).                           
true_test() -> ?a(true, <<16#03>>).


%% integers -268435456 to 268435455 are encoded as integers
integer_test_() ->
  [     
    ?_a(-268435456, <<16#04,16#C0,16#80,16#80,16#00>>),
    ?_a(-10, <<16#04,16#FF,16#FF,16#FF,16#F6>>),
    ?_a(-1, <<16#04,16#FF,16#FF,16#FF,16#FF>>),
    ?_a(0, <<16#04,16#00>>),
    ?_a(127, <<16#04,16#7F>>), 
    ?_a(128, <<16#04,16#81,16#00>>),
    ?_a(16383, <<16#04,16#FF,16#7F>>),
    ?_a(16384, <<16#04,16#81,16#80,16#00>>),
    ?_a(2097151, <<16#04,16#FF,16#FF,16#7F>>),
    ?_a(2097152,<<16#04,16#80,16#C0,16#80,16#00>>), 
    ?_a(268435455, <<16#04,16#BF,16#FF,16#FF,16#FF>>)
  ].    


%% Integer values -1.79e308 to -268435457   and    268435456 to 1.79e308 are encoded as doubles
integer_outside_range_test_() ->
  [
    ?_assertEqual(<<16#05,16#41,16#B0,16#00,16#00,16#00,16#00,16#00,16#00>>, amf3:encode(268435456)),
    ?_assertEqual(<<16#05,16#C1,16#B0,16#00,16#00,16#01,16#00,16#00,16#00>>, amf3:encode(-268435457))
  ].


%% All floating point Numbers are enoded as doubles
%% These constants of the AS3 Number class are also encoded as doubles >> -infinity, infinity, nan  
double_test_() ->
  [ 
    ?_a(268435456.0, <<16#05,16#41,16#B0,16#00,16#00,16#00,16#00,16#00,16#00>>),
    ?_a(268435456.5, <<16#05,16#41,16#B0,16#00,16#00,16#00,16#80,16#00,16#00>>),
    ?_a(10.1, <<16#05,16#40,16#24,16#33,16#33,16#33,16#33,16#33,16#33>>),
    ?_a(-268435457.0, <<16#05,16#C1,16#B0,16#00,16#00,16#01,16#00,16#00,16#00>>),
    ?_a(-72057594037927940.0, <<16#05,16#C3,16#70,16#00,16#00,16#00,16#00,16#00,16#00>>),
    ?_a(72057594037927940.0, <<16#05,16#43,16#70,16#00,16#00,16#00,16#00,16#00,16#00>>), 
    ?_a(1.79e308, <<16#05,16#7F,16#EF,16#DC,16#F1,16#58,16#AD,16#BB,16#99>>),
    ?_a(-1.79e308, <<16#05,16#FF,16#EF,16#DC,16#F1,16#58,16#AD,16#BB,16#99>>),
    ?_a(infinity, <<16#05,16#7F,16#F0,16#00,16#00,16#00,16#00,16#00,16#00>>),
    ?_a('-infinity', <<16#05,16#FF,16#F0,16#00,16#00,16#00,16#00,16#00,16#00>>),
    ?_a(nan, <<16#05,16#FF,16#F8,16#00,16#00,16#00,16#00,16#00,16#00>>)
  ].  
  

string_test_() ->
  [
    ?_a(<<"">>, <<16#06,16#01>>),
    ?_a(<<"hello">>, <<16#06,16#0B,"hello">>),
    ?_a(<<"hello world">>, <<16#06,16#17,"hello world">>),
    ?_a(<<"œ∑´®†¥¨ˆøπ“‘«åß∂©˙∆˚¬…æΩç√˜µ≤≥÷">>, <<16#06,16#81,16#11,"œ∑´®†¥¨ˆøπ“‘«åß∂©˙∆˚¬…æΩç√˜µ≤≥÷">>)
  ].  


%% atoms are encoded as strings
string_atom_test_() ->
  [
    ?_assertEqual(amf3:encode(<<"hello">>), amf3:encode(hello)),
    ?_assertEqual(amf3:encode(<<"hello world">>), amf3:encode('hello world'))  
  ].  
  
  
string_refernece_test_() ->
  [
    ?_a([<<"hello">>,<<"world">>,<<"hello">>,<<"world">>,<<"hello">>,<<"world">>],
        <<16#09,16#0D,16#01,16#06,16#0B,"hello",16#06,16#0B,"world",16#06,16#00,16#06,16#02,16#06,16#00,16#06,16#02>>),

    ?_a({object,<<>>, dict:store(b, <<"hello">>, dict:store(a, <<"hello">>, dict:new()))}, 
        <<16#0A,16#0B,16#01,16#03,"a",16#06,16#0B,"hello",16#03,"b",16#06,16#02,16#01>>)         
  ].
  

xmldoc_test_() ->
  [
    ?_a({xmldoc,<<"<text>hello</text>">>}, <<16#07,16#25,"<text>hello</text>">>)
  ].


xmldoc_reference_test_() ->
  [
    ?_a({object,<<>>,dict:store(b,{xmldoc, <<"<hello>test</hello>">>},
                                dict:store(a,{xmldoc, <<"<hello>test</hello>">>},dict:new()))},
    <<16#0A,16#0B,16#01,16#03,"a",16#07,16#27,"<hello>test</hello>",16#03,"b",16#07,16#02,16#01>>)
  ].
  
  
date_test_() -> 
  [
    ?_a({date,1260103478896.0},<<16#08,16#01,16#42,16#72,16#56,16#40,16#52,16#E7,16#00,16#00>>)
  ].
  
  
date_reference_test_() ->
  [
    ?_a({object,<<>>,dict:store(b,{date,1261385577404.0},dict:store(a,{date,1261385577404.0},dict:new()))},
        <<16#0A,16#0B,16#01,16#03,16#61,16#08,16#01,16#42,16#72,16#5B,16#07,16#07,16#3B,16#C0,
          16#00,16#03,16#62,16#08,16#02,16#01>>)
  ].
  
  
array_test_() ->
  [
    %% dense
    ?_a([100],<<16#09,16#03,16#01,16#04,16#64>>),
    ?_a([100,200],<<16#09,16#05,16#01,16#04,16#64,16#04,16#81,16#48>>),
    ?_a([null,[100,200],false],<<16#09,16#07,16#01,16#01,16#09,16#05,16#01,16#04,16#64,16#04,16#81,16#48,16#02>>),

    %% associative only
    ?_a([{a,100},{b,200}],<<16#09,16#01,16#03,16#61,16#04,16#64,16#03,16#62,16#04,16#81,16#48,16#01>>),
    
    %% mixed  
    ?_a([{a,100},{b,200},500,600],
      <<16#09,16#05,16#03,16#61,16#04,16#64,16#03,16#62,16#04,16#81,16#48,16#01,16#04,16#83,16#74,16#04,16#84,16#58>>)
  ].


array_reference_test_() ->
  [
    ?_a({object,<<>>,dict:store(b,[100,200],dict:store(a,[100,200],dict:new()))},
        <<16#0A,16#0B,16#01,16#03,16#61,16#09,16#05,16#01,16#04,16#64,16#04,16#81,16#48,16#03,16#62,
          16#09,16#02,16#01>>) 
  ].
  
  
xml_test_() ->
  [
    ?_a({xml,<<"<text>hello</text>">>},<<16#0B,16#25,"<text>hello</text>">>)
  ].


xml_reference_test_() ->
  [
    ?_a({object,<<>>,dict:store(b,{xml, <<"<hello>test</hello>">>},
                                dict:store(a,{xml, <<"<hello>test</hello>">>},dict:new()))},
    <<16#0A,16#0B,16#01,16#03,"a",16#0B,16#27,"<hello>test</hello>",16#03,"b",16#0B,16#02,16#01>>)
  ].


bytearray_test_() -> 
  [
    ?_a({bytearray,<<100,200>>},<<16#0C,16#05,100,200>>),
    ?_a({bytearray,<<2#00000001>>},<<12,3,1>>)
  ].


bytearray_reference_test_() ->
  [
    ?_a({object,<<>>,dict:store(b,{bytearray,<<100,200>>},dict:store(a,{bytearray,<<100,200>>},dict:new()))},
        <<16#0A,16#0B,16#01,16#03,16#61,16#0C,16#05,16#64,16#C8,16#03,16#62,16#0C,16#02,16#01>>)  
  ].


decode_object_test_() ->
  [
    ?_a({object,<<>>,dict:store(b,200,dict:store(a,100,dict:new()))},
        <<16#0A,16#0B,16#01,16#03,16#61,16#04,16#64,16#03,16#62,16#04,16#81,16#48,16#01>>),

    ?_a({object,<<"TestClass">>,dict:store(n2,<<"world">>,dict:store(n1,<<"hello">>,dict:new()))},
        <<16#0A,16#23,16#13,"TestClass",16#05,"n1",16#05,"n2",16#06,16#0B,"hello",16#06,16#0B,"world">>),

    ?_a({object,<<>>,dict:store(b,{object,<<>>,dict:new()},dict:store(a,{object,<<>>,dict:new()},dict:new()))},
        <<16#0A,16#0B,16#01,16#03,16#61,16#0A,16#01,16#01,16#03,16#62,16#0A,16#02,16#01>>),

    ?_a({object,<<>>,dict:store(a,{object,<<"TestClass">>, dict:store(n2,null,
                                                                      dict:store(n1,null,dict:new()))},dict:new())},
         <<16#0A,16#0B,16#01,16#03,16#61,16#0A,16#23,16#13,16#54,16#65,16#73,16#74,16#43,16#6C,
           16#61,16#73,16#73,16#05,16#6E,16#31,16#05,16#6E,16#32,16#01,16#01,16#01>>),

    ?_a({object,<<>>,dict:store(b,{object,<<>>,dict:store(y,200,dict:store(x,100,dict:new()))},
                              dict:store(a,{object,<<>>,dict:store(y,200,dict:store(x,100,dict:new()))},dict:new()))},
       <<16#0A,16#0B,16#01,16#03,16#61,16#0A,16#01,16#03,16#78,16#04,16#64,16#03,16#79,16#04,16#81,
       16#48,16#01,16#03,16#62,16#0A,16#02,16#01>>),

    %% trait reference, object reference
    ?_a({object,<<>>,dict:store(b,{object,<<"TestClass">>,dict:store(n2,null,dict:store(n1,null,dict:new()))},
        dict:store(a,{object,<<"TestClass">>,dict:store(n2,null,dict:store(n1, null,dict:new()))},dict:new()))},
        <<16#0A,16#0B,16#01,16#03,16#61,16#0A, 16#23,16#13,16#54,16#65,16#73,16#74,
          16#43,16#6C,16#61,16#73,16#73,16#05,16#6E,16#31,16#05,16#6E,16#32,16#01,
          16#01,16#03,16#62,16#0A,16#05,16#01,16#01,16#01>>),


    %% trait reference, object reference
    ?_a({object,<<>>,dict:store(b,{object,<<"TestClass">>,dict:store(n2,<<"hello">>,dict:store(n1,<<"hello">>,
         dict:new()))},dict:store(a,{object,<<"TestClass">>,dict:store(n2,<<"hello">>, dict:store(n1,<<"hello">>,
         dict:new()))},dict:new()))},
         <<16#0A,16#0B,16#01,16#03,16#61,16#0A,16#23,16#13,16#54,16#65,16#73,16#74,
           16#43,16#6C,16#61,16#73,16#73,16#05,16#6E,16#31,16#05,16#6E,16#32,16#06,
           16#0B,16#68,16#65,16#6C,16#6C,16#6F,16#06,16#08,16#03,16#62,16#0A,16#02,16#01>>)
  ].