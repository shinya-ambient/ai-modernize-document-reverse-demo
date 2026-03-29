      **FREE
      // ============================================================
      // プログラム名: ORDENTR
      // 概要        : 受注入力処理
      // 作成日      : 1998/04/15  田中
      // 更新履歴    :
      //   2001/06/20 佐藤  消費税対応（5%）
      //   2004/11/10 鈴木  得意先与信チェック追加
      //   2008/03/01 佐藤  内税/外税区分対応
      //   2014/04/01 山田  消費税8%対応
      //   2019/10/01 ???   軽減税率対応（暫定）
      //   2023/01/15 派遣  インボイス対応（急ぎ）
      // ============================================================

      // ファイル定義
      DCL-F ORDERHDR  DISK(*EXT) USAGE(*UPDATE:*OUTPUT) KEYED;
      DCL-F ORDERDTL  DISK(*EXT) USAGE(*UPDATE:*OUTPUT) KEYED;
      DCL-F CUSTMAST  DISK(*EXT) USAGE(*INPUT) KEYED;
      DCL-F ITEMMAST  DISK(*EXT) USAGE(*INPUT) KEYED;
      DCL-F INVMAST   DISK(*EXT) USAGE(*UPDATE) KEYED;
      DCL-F PRICMAST  DISK(*EXT) USAGE(*INPUT) KEYED;
      DCL-F ORDSCR    WORKSTN SFILE(DTLSFL:SFLRRN)
                       INDDS(INDICATORS);

      // インジケータDS
      DCL-DS INDICATORS;
        IND_EXIT      IND POS(3);
        IND_CONFIRM   IND POS(5);
        IND_ROLLUP    IND POS(7);
        IND_ROLLDOWN  IND POS(8);
        IND_SFLCLR    IND POS(30);
        IND_SFLDSP    IND POS(31);
        IND_SFLDSPCTL IND POS(32);
        IND_SFLEND    IND POS(33);
        IND_PROTECT   IND POS(40);
        IND_ERR_CST   IND POS(51);
        IND_ERR_ITM   IND POS(52);
        IND_ERR_QTY   IND POS(53);
        IND_ERR_CRD   IND POS(54);
        IND_ERR_STK   IND POS(55);
      END-DS;

      // 作業変数
      DCL-S SFLRRN      PACKED(4:0);
      DCL-S W_ORDNO     CHAR(10);
      DCL-S W_ORDDATE   DATE;
      DCL-S W_CUSTCD    CHAR(8);
      DCL-S W_CUSTNAME  CHAR(40);
      DCL-S W_ITEMCD    CHAR(12);
      DCL-S W_QTY       PACKED(9:0);
      DCL-S W_UPRICE    PACKED(11:2);
      DCL-S W_AMT       PACKED(13:2);
      DCL-S W_TAXAMT    PACKED(13:2);
      DCL-S W_TOTALAMT  PACKED(15:2);
      DCL-S W_TAXRATE   PACKED(5:3);
      DCL-S W_TAXKBN    CHAR(1);
      DCL-S W_LINENO    PACKED(3:0);
      DCL-S W_CREDIT    PACKED(13:2);
      DCL-S W_CRUSED    PACKED(13:2);
      DCL-S W_STKSUU    PACKED(9:0);
      DCL-S W_HIKISUU   PACKED(9:0);
      DCL-S W_ERRFLG    CHAR(1);
      DCL-S W_MSGID     CHAR(7);
      DCL-S W_DELKBN    CHAR(1);
      DCL-S W_NOESSION  PACKED(5:0);
      DCL-S W_PRICTYP   CHAR(2);
      DCL-S W_DISCRATE  PACKED(5:2);
      DCL-S W_WAESSION  CHAR(2);
      DCL-S W_SHIPDT    DATE;
      DCL-S W_SEESSION  CHAR(2);
      DCL-S W_CNVFLG    CHAR(1);  // 2023追加 インボイス

      // 消費税率テーブル  ※2019暫定対応 後で直す
      DCL-DS TAXRATES DIM(3);
        TX_KBN    CHAR(1);
        TX_RATE   PACKED(5:3);
      END-DS;

      // 受注番号採番DS
      DCL-DS ORDNODS DTAARA(*AUTO);
        LAST_ORDNO PACKED(10:0);
      END-DS;

      // ===== メイン処理 =====
      EXSR INIT;

      DOW NOT IND_EXIT;
        WRITE HEADER;
        EXFMT CONTROL;

        SELECT;
          WHEN IND_EXIT;
            LEAVE;
          WHEN IND_CONFIRM;
            EXSR VALIDATE;
            IF W_ERRFLG = ' ';
              EXSR CONFIRM_ORDER;
            ENDIF;
          OTHER;
            EXSR PROCESS_INPUT;
        ENDSL;
      ENDDO;

      *INLR = *ON;
      RETURN;

      // ===== 初期処理 =====
      BEGSR INIT;
        // 消費税率セット   ※TODO: マスタ化する（2019 暫定でハードコード）
        TX_KBN(1) = '0';    // 標準税率
        TX_RATE(1) = 0.100;
        TX_KBN(2) = '1';    // 軽減税率
        TX_RATE(2) = 0.080;
        TX_KBN(3) = '2';    // 非課税
        TX_RATE(3) = 0.000;

        W_ORDDATE = %DATE();
        W_SHIPDT  = %DATE() + %DAYS(3);  // デフォ3営業日後 ※祝日未考慮
        W_LINENO  = 0;
        W_ERRFLG  = ' ';
        W_CNVFLG  = ' ';

        // 受注番号採番
        IN ORDNODS;
        LAST_ORDNO += 1;
        W_ORDNO = %EDITC(LAST_ORDNO:'X');
        OUT ORDNODS;

        EXSR CLR_SFL;
      ENDSR;

      // ===== サブファイルクリア =====
      BEGSR CLR_SFL;
        IND_SFLCLR = *ON;
        WRITE DTLCTL;
        IND_SFLCLR = *OFF;
        SFLRRN = 0;
      ENDSR;

      // ===== 入力処理 =====
      BEGSR PROCESS_INPUT;
        // 得意先チェック
        IF S_CUSTCD <> ' ';
          CHAIN S_CUSTCD CUSTMAST;
          IF %FOUND(CUSTMAST);
            W_CUSTCD   = C_CUSTCD;
            W_CUSTNAME = C_CUSTNAME;
            W_PRICTYP  = C_PRICTYP;
            W_DISCRATE = C_DISCRATE;
            W_DELKBN   = C_DELKBN;
            W_CREDIT   = C_CREDIT;
            W_CRUSED   = C_CRUSED;
            S_CUSTNAME = W_CUSTNAME;
            IND_ERR_CST = *OFF;
          ELSE;
            IND_ERR_CST = *ON;
            S_ERRMSG = 'E001:得意先が見つかりません';
          ENDIF;
        ENDIF;

        // 明細行入力処理
        READC DTLSFL;
        DOW NOT %EOF;
          EXSR PROCESS_DTL;
          READC DTLSFL;
        ENDDO;

        EXSR CALC_TOTAL;
      ENDSR;

      // ===== 明細行処理 =====
      BEGSR PROCESS_DTL;
        IND_ERR_ITM = *OFF;
        IND_ERR_QTY = *OFF;
        IND_ERR_STK = *OFF;

        // 商品マスタチェック
        CHAIN D_ITEMCD ITEMMAST;
        IF NOT %FOUND(ITEMMAST);
          IND_ERR_ITM = *ON;
          D_ERRMSG = 'E002:商品が見つかりません';
          LEAVESR;
        ENDIF;

        // 数量チェック
        IF D_QTY <= 0;
          IND_ERR_QTY = *ON;
          D_ERRMSG = 'E003:数量は1以上を入力してください';
          LEAVESR;
        ENDIF;

        // 在庫チェック（出荷区分が即日の場合のみ）
        // 2004/11追加 鈴木
        IF W_DELKBN = '1';  // 即日出荷
          CHAIN D_ITEMCD INVMAST;
          IF %FOUND(INVMAST);
            W_STKSUU = I_STKSUU - I_HIKISUU;
            IF W_STKSUU < D_QTY;
              IND_ERR_STK = *ON;
              D_ERRMSG = 'W001:在庫不足 有効在庫=' +
                         %CHAR(W_STKSUU);
              // ※エラーにはしない（警告のみ） 2008変更
            ENDIF;
          ENDIF;
        ENDIF;

        // 単価取得
        EXSR GET_PRICE;

        // 金額計算
        D_AMT = D_QTY * D_UPRICE;

        // 値引計算  ※特殊得意先は別ロジック
        IF W_PRICTYP = 'S1';
          // 大口特約 2001追加
          IF D_AMT >= 1000000;
            D_AMT = D_AMT * 0.95;
          ELSEIF D_AMT >= 500000;
            D_AMT = D_AMT * 0.97;
          ELSEIF D_AMT >= 100000;
            D_AMT = D_AMT * 0.98;
          ENDIF;
        ELSEIF W_PRICTYP = 'S2';
          // 系列店特約
          D_AMT = D_AMT * (1 - W_DISCRATE / 100);
        ELSEIF W_PRICTYP = 'G1';
          // 官公庁   ※消費税処理が異なる→CALC_TAXで分岐
          // 何もしない
        ENDIF;

        // 消費税計算
        EXSR CALC_TAX;
        D_TAXAMT = W_TAXAMT;

        UPDATE DTLSFL;
      ENDSR;

      // ===== 単価取得 =====
      BEGSR GET_PRICE;
        // 価格マスタから取得（得意先別→品目グループ別→標準の順に検索）
        // 2008/03 佐藤 ロジック変更
        CHAIN (W_CUSTCD:D_ITEMCD) PRICMAST;
        IF %FOUND(PRICMAST);
          D_UPRICE = P_UPRICE;
        ELSE;
          // 品目グループ別価格
          CHAIN ('*GRP':D_ITEMCD) PRICMAST;
          IF %FOUND(PRICMAST);
            D_UPRICE = P_UPRICE;
          ELSE;
            // 標準価格
            D_UPRICE = I_STDPRICE;
          ENDIF;
        ENDIF;

        // 内税の場合、税抜に変換  ※2008追加
        IF I_TAXKBN = '0' AND C_TAXCALC = 'I';
          D_UPRICE = D_UPRICE / (1 + TX_RATE(1));
        ENDIF;
      ENDSR;

      // ===== 消費税計算 =====
      BEGSR CALC_TAX;
        W_TAXKBN = I_TAXKBN;

        // 税率決定
        SELECT;
          WHEN W_TAXKBN = '0';  // 標準
            W_TAXRATE = TX_RATE(1);
          WHEN W_TAXKBN = '1';  // 軽減
            W_TAXRATE = TX_RATE(2);
          WHEN W_TAXKBN = '2';  // 非課税
            W_TAXRATE = TX_RATE(3);
          OTHER;
            W_TAXRATE = TX_RATE(1);  // デフォルト標準
        ENDSL;

        // 消費税額計算
        // 官公庁は明細単位で端数処理（切捨）
        // それ以外は伝票単位（CALC_TOTALで処理）
        IF W_PRICTYP = 'G1';
          W_TAXAMT = %INT(D_AMT * W_TAXRATE);
        ELSE;
          W_TAXAMT = D_AMT * W_TAXRATE;
          // ※伝票合計時に端数処理
        ENDIF;
      ENDSR;

      // ===== 合計計算 =====
      BEGSR CALC_TOTAL;
        S_SUBTOTAL = 0;
        S_TAXTOTAL = 0;

        // 税率別合計用  ※2019暫定
        DCL-S W_TAX10AMT  PACKED(13:2) INZ(0);
        DCL-S W_TAX08AMT  PACKED(13:2) INZ(0);
        DCL-S W_TAX00AMT  PACKED(13:2) INZ(0);

        SFLRRN = 1;
        DOW SFLRRN <= W_LINENO;
          CHAIN SFLRRN DTLSFL;
          IF %FOUND;
            S_SUBTOTAL += D_AMT;

            // 税率別集計（インボイス対応 2023追加）
            SELECT;
              WHEN D_TAXKBN = '0';
                W_TAX10AMT += D_AMT;
              WHEN D_TAXKBN = '1';
                W_TAX08AMT += D_AMT;
              WHEN D_TAXKBN = '2';
                W_TAX00AMT += D_AMT;
            ENDSL;
          ENDIF;
          SFLRRN += 1;
        ENDDO;

        // 伝票単位消費税（端数切捨）
        // ※官公庁以外
        IF W_PRICTYP <> 'G1';
          S_TAXTOTAL = %INT(W_TAX10AMT * 0.10)
                     + %INT(W_TAX08AMT * 0.08);
        ELSE;
          // 官公庁は明細単位合算済
          SFLRRN = 1;
          DOW SFLRRN <= W_LINENO;
            CHAIN SFLRRN DTLSFL;
            IF %FOUND;
              S_TAXTOTAL += D_TAXAMT;
            ENDIF;
            SFLRRN += 1;
          ENDDO;
        ENDIF;

        S_TOTAL = S_SUBTOTAL + S_TAXTOTAL;
      ENDSR;

      // ===== 入力検証 =====
      BEGSR VALIDATE;
        W_ERRFLG = ' ';

        // 得意先必須チェック
        IF W_CUSTCD = ' ';
          W_ERRFLG = 'E';
          S_ERRMSG = 'E010:得意先コードを入力してください';
          LEAVESR;
        ENDIF;

        // 明細行存在チェック
        IF W_LINENO = 0;
          W_ERRFLG = 'E';
          S_ERRMSG = 'E011:明細行を入力してください';
          LEAVESR;
        ENDIF;

        // 与信チェック  2004/11 鈴木追加
        IF W_CREDIT > 0;
          IF (W_CRUSED + S_TOTAL) > W_CREDIT;
            W_ERRFLG = 'E';
            IND_ERR_CRD = *ON;
            S_ERRMSG = 'E020:与信限度額を超過しています '
                     + '限度額=' + %CHAR(W_CREDIT)
                     + ' 使用額=' + %CHAR(W_CRUSED + S_TOTAL);
            LEAVESR;
          ENDIF;
        ENDIF;

        // 出荷日チェック ※土日は不可（祝日は未対応のまま）
        // 2008追加
        DCL-S W_DOW PACKED(1:0);
        W_DOW = %REM(%DIFF(W_SHIPDT:D'1900-01-07':*DAYS):7);
        IF W_DOW = 0 OR W_DOW = 6;
          W_ERRFLG = 'W';
          S_ERRMSG = 'W010:出荷日が土日です。確認してください';
          // 警告のみ、確認キーで続行可
        ENDIF;
      ENDSR;

      // ===== 受注確定処理 =====
      BEGSR CONFIRM_ORDER;
        // ヘッダ書込み
        H_ORDNO    = W_ORDNO;
        H_ORDDATE  = %DEC(W_ORDDATE:*ISO);
        H_CUSTCD   = W_CUSTCD;
        H_SUBTOTAL = S_SUBTOTAL;
        H_TAXTOTAL = S_TAXTOTAL;
        H_TOTAL    = S_TOTAL;
        H_SHIPDT   = %DEC(W_SHIPDT:*ISO);
        H_STATUS   = '10';     // 10:受付済
        H_ENTRY_PGM = 'ORDENTR';
        H_ENTRY_USR = %USER();
        H_ENTRY_DT  = %DEC(%TIMESTAMP():*ISO);
        H_INVFLG   = W_CNVFLG;  // インボイスフラグ 2023追加
        WRITE ORDHDR;

        // 明細書込み
        SFLRRN = 1;
        DOW SFLRRN <= W_LINENO;
          CHAIN SFLRRN DTLSFL;
          IF %FOUND;
            L_ORDNO   = W_ORDNO;
            L_LINENO  = SFLRRN;
            L_ITEMCD  = D_ITEMCD;
            L_QTY     = D_QTY;
            L_UPRICE  = D_UPRICE;
            L_AMT     = D_AMT;
            L_TAXKBN  = D_TAXKBN;
            L_TAXAMT  = D_TAXAMT;
            WRITE ORDDTL;

            // 引当数更新  ※即日出荷の場合
            IF W_DELKBN = '1';
              CHAIN D_ITEMCD INVMAST;
              IF %FOUND(INVMAST);
                I_HIKISUU += D_QTY;
                UPDATE INVMST;
              ENDIF;
            ENDIF;
          ENDIF;
          SFLRRN += 1;
        ENDDO;

        // 得意先与信使用額更新
        CHAIN W_CUSTCD CUSTMAST;
        IF %FOUND(CUSTMAST);
          C_CRUSED += S_TOTAL;
          UPDATE CUSTMST;
        ENDIF;

        S_ERRMSG = 'I001:受注番号 ' + W_ORDNO + ' を登録しました';

        // 初期化して次の受注入力へ
        EXSR INIT;
      ENDSR;
