Require Import Coq.Strings.String.
Require Import AutoDB.

Definition Market := string.
Definition StockType := nat.
Definition StockCode := nat.
Definition Date      := nat.
Definition Timestamp := nat.

Definition TYPE := "TYPE".
Definition MARKET := "MARKET".
Definition STOCK_CODE := "STOCK_CODE".
Definition FULL_NAME := "FULL_NAME".

Definition DATE := "DATE".
Definition TIME := "TIME".
Definition PRICE := "PRICE".
Definition VOLUME := "VOLUME".

Definition STOCKS := "STOCKS".
Definition TRANSACTIONS := "TRANSACTIONS".

Definition StocksSchema :=
  Query Structure Schema
    [ relation STOCKS has
              schema <STOCK_CODE :: StockCode,
                      FULL_NAME :: string,
                      MARKET :: Market,
                      TYPE :: StockType>
              where attributes [FULL_NAME; MARKET; TYPE] depend on [STOCK_CODE]; (* uniqueness, really *)
      relation TRANSACTIONS has
              schema <STOCK_CODE :: nat,
                      DATE :: Date,
                      TIME :: Timestamp,
                      PRICE :: N,
                      VOLUME :: N>
              where attributes [PRICE] depend on [STOCK_CODE; TIME] ]
    enforcing [attribute STOCK_CODE for TRANSACTIONS references STOCKS].

Definition StocksSig : ADTSig :=
  ADTsignature {
      Constructor "Init"               : unit                              -> rep,
      Method "AddStock"           : rep x (StocksSchema#STOCKS)       -> rep x bool,
      Method "AddTransaction"     : rep x (StocksSchema#TRANSACTIONS) -> rep x bool,
      Method "TotalVolume"        : rep x (StockCode * Date)          -> rep x N,
      Method "MaxPrice"           : rep x (StockCode * Date)          -> rep x option N,
      Method "TotalActivity"      : rep x (StockCode * Date)          -> rep x nat,
      Method "LargestTransaction" : rep x (StockType * Date)          -> rep x option N
    }.

Definition StocksSpec : ADT StocksSig :=
  QueryADTRep StocksSchema {
    Def Constructor "Init" (_: unit) : rep := empty,

    update "AddStock" (stock: StocksSchema#STOCKS) : bool :=
        Insert stock into STOCKS,

    update "AddTransaction" (transaction : StocksSchema#TRANSACTIONS) : bool :=
        Insert transaction into TRANSACTIONS,

    query "TotalVolume" (params: StockCode * Date) : N :=
      SumN (For (transaction in TRANSACTIONS)
            Where (transaction!STOCK_CODE = fst params)
            Where (transaction!DATE = snd params)
            Return transaction!VOLUME),

    query "MaxPrice" (params: StockCode * Date) : option N :=
      MaxN (For (transaction in TRANSACTIONS)
            Where (transaction!STOCK_CODE = fst params)
            Where (transaction!DATE = snd params)
            Return transaction!PRICE),

    query "TotalActivity" (params: StockCode * Date) : nat :=
      Count (For (transaction in TRANSACTIONS)
            Where (transaction!STOCK_CODE = fst params)
            Where (transaction!DATE = snd params)
            Return ()),

    query "LargestTransaction" (params: StockType * Date) : option N :=
      MaxN (For (stock in STOCKS) (transaction in TRANSACTIONS)
            Where (stock!TYPE = fst params)
            Where (transaction!DATE = snd params)
            Where (stock!STOCK_CODE = transaction!STOCK_CODE)
            Return (N.mul transaction!PRICE transaction!VOLUME))
}.

Definition StocksDB :
  Sharpened StocksSpec.
Proof.

  unfold StocksSpec.

  (* First, we unfold various definitions and drop constraints *)
  start honing QueryStructure.

  make simple indexes using [[TYPE; STOCK_CODE]; [DATE; STOCK_CODE]].

  Time plan. (* ~10 minutes*)

    FullySharpenQueryStructure StocksSchema Index.

    Time implement_bag_methods. (* 106 seconds *)
    Time implement_bag_methods. (* 228 seconds *)
    Time implement_bag_methods. (*  37 seconds *)
    Time implement_bag_methods. (*  33 seconds *)
    Time implement_bag_methods. (*  31 seconds *)
    Time implement_bag_methods. (*  90 seconds*)

    Time Defined.
