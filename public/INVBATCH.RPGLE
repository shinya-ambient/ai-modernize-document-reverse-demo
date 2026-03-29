      **FREE
      // ============================================================
      // プログラム名: INVBATCH
      // 概要        : 在庫引当・補充計算バッチ
      // 実行時間    : 毎日 22:00（JOBスケジューラ NIGHTJOB1）
      // 作成日      : 1997/08/20  田中
      // 更新履歴    :
      //   1999/03/15 佐藤  安全在庫計算ロジック追加
      //   2002/07/01 鈴木  倉庫間移動対応
      //   2005/09/20 外注  ロット管理対応
      //   2010/04/01 山田  複数倉庫対応（急ぎ）
      //   2015/01/xx      発注点自動計算を追加したが不具合あり
      //                    手動に戻した（コメントアウトのまま残す）
      //   2020/06/01 ???   コロナ対応 安全在庫係数変更
      // ============================================================

      DCL-F INVMAST   DISK(*EXT) USAGE(*UPDATE) KEYED;
      DCL-F ITEMMAST  DISK(*EXT) USAGE(*INPUT) KEYED;
      DCL-F ORDERDTL  DISK(*EXT) USAGE(*INPUT) KEYED;
      DCL-F PORMAST   DISK(*EXT) USAGE(*OUTPUT);   // 発注データ
      DCL-F INVHIST   DISK(*EXT) USAGE(*OUTPUT);   // 在庫履歴
      DCL-F WHSMAST   DISK(*EXT) USAGE(*INPUT) KEYED;  // 2010追加
      DCL-F LOTMAST   DISK(*EXT) USAGE(*UPDATE) KEYED; // 2005追加
      DCL-F INVLOG    PRINTER OFLIND(IND_OFL);

      DCL-S IND_OFL   IND;
      DCL-S W_ITEMCD  CHAR(12);
      DCL-S W_STKSUU  PACKED(9:0);
      DCL-S W_HIKISUU PACKED(9:0);
      DCL-S W_YUKSUU  PACKED(9:0);  // 有効在庫
      DCL-S W_ANSUU   PACKED(9:0);  // 安全在庫
      DCL-S W_HATSUU  PACKED(9:0);  // 発注点
      DCL-S W_LOTQTY  PACKED(9:0);  // ロット数
      DCL-S W_ORDQTY  PACKED(9:0);  // 発注数
      DCL-S W_AVGSUU  PACKED(9:2);  // 平均出庫数
      DCL-S W_LEADTM  PACKED(3:0);  // リードタイム（日）
      DCL-S W_SATEFCT PACKED(3:2);  // 安全在庫係数
      DCL-S W_WHSCD   CHAR(4);
      DCL-S W_LOTNO   CHAR(15);
      DCL-S W_EXPDT   DATE;
      DCL-S W_PORNO   PACKED(10:0);
      DCL-S W_ERRCNT  PACKED(5:0) INZ(0);
      DCL-S W_PORCNT  PACKED(5:0) INZ(0);
      DCL-S W_PRCCNT  PACKED(7:0) INZ(0);
      DCL-S W_SESSION CHAR(1);
      DCL-S W_SEASON  CHAR(2);
      DCL-S W_CATCD   CHAR(3);

      // 発注番号DTAARA
      DCL-DS PORNODS DTAARA(*AUTO);
        LAST_PORNO PACKED(10:0);
      END-DS;

      // 過去出庫数計算用DS
      DCL-DS SHIPDS;
        SH_M01  PACKED(9:0);  // 1ヶ月前
        SH_M02  PACKED(9:0);  // 2ヶ月前
        SH_M03  PACKED(9:0);  // 3ヶ月前
        SH_M06  PACKED(9:0);  // 6ヶ月前  ※途中の月は省略
        SH_M12  PACKED(9:0);  // 12ヶ月前
      END-DS;

      // ===== メイン処理 =====
      EXSR INIT_BATCH;
      EXSR PRT_HEADER;

      READ INVMAST;
      DOW NOT %EOF(INVMAST);
        W_PRCCNT += 1;
        EXSR PROC_ITEM;
        READ INVMAST;
      ENDDO;

      EXSR PRT_SUMMARY;
      EXSR END_BATCH;

      *INLR = *ON;
      RETURN;

      // ===== バッチ初期処理 =====
      BEGSR INIT_BATCH;
        // 安全在庫係数
        // 2020/06 コロナ対応で1.5→2.0に変更
        // ※戻し忘れ注意
        W_SATEFCT = 2.00;

        // 季節係数判定
        W_SEASON = %SUBST(%CHAR(%DATE():*ISO):6:2);

        IN PORNODS;
      ENDSR;

      // ===== 品目別処理 =====
      BEGSR PROC_ITEM;
        W_ITEMCD = I_ITEMCD;

        // 品目マスタ読込
        CHAIN W_ITEMCD ITEMMAST;
        IF NOT %FOUND(ITEMMAST);
          W_ERRCNT += 1;
          EXSR PRT_ERR;
          LEAVESR;
        ENDIF;

        // 削除・廃番品はスキップ
        IF IT_DELFLG = '1' OR IT_STATUS = '9';
          LEAVESR;
        ENDIF;

        W_CATCD = IT_CATCD;

        // 有効在庫計算
        W_STKSUU  = I_STKSUU;
        W_HIKISUU = I_HIKISUU;
        W_YUKSUU  = W_STKSUU - W_HIKISUU;

        // ロット期限チェック  2005追加
        IF IT_LOTFLG = '1';
          EXSR CHK_LOT;
        ENDIF;

        // 平均出庫数計算
        EXSR CALC_AVG_SHIP;

        // 安全在庫計算
        EXSR CALC_SAFETY;

        // 発注点計算
        W_HATSUU = %INT(W_AVGSUU * W_LEADTM) + W_ANSUU;

        // 発注判定
        IF W_YUKSUU <= W_HATSUU;
          EXSR CREATE_PO;
        ENDIF;

        // 在庫履歴出力
        EXSR WRITE_HIST;

        // 引当数リセット（出荷済み分）
        // ※本来は出荷確定時にやるべきだが、
        //   出荷プログラム(SHPCONF)側の改修が間に合わず
        //   バッチで暫定対応  2010 山田
        IF I_SHPFLG = '1';
          I_STKSUU  -= I_HIKISUU;
          I_HIKISUU  = 0;
          I_SHPFLG   = '0';
          UPDATE INVMST;
        ENDIF;
      ENDSR;

      // ===== ロット期限チェック =====
      BEGSR CHK_LOT;
        CHAIN W_ITEMCD LOTMAST;
        DOW %FOUND(LOTMAST);
          W_LOTNO = LT_LOTNO;
          W_EXPDT = %DATE(LT_EXPDT:*ISO);

          // 期限30日以内は警告
          IF %DIFF(W_EXPDT:%DATE():*DAYS) <= 30
             AND %DIFF(W_EXPDT:%DATE():*DAYS) > 0;
            EXSR PRT_LOTWARN;
          ENDIF;

          // 期限切れは有効在庫から除外
          IF W_EXPDT < %DATE();
            W_YUKSUU -= LT_LOTSUU;
            LT_STATUS = '9';  // 期限切れ
            UPDATE LOTMST;
            EXSR PRT_LOTEXP;
          ENDIF;

          READE W_ITEMCD LOTMAST;
        ENDDO;
      ENDSR;

      // ===== 平均出庫数計算 =====
      BEGSR CALC_AVG_SHIP;
        CLEAR SHIPDS;

        // 過去3ヶ月の出荷実績を取得
        // ※本当はORDERDTLから集計すべきだが
        //   パフォーマンスが悪いのでINVMASTの月次集計項目を使う
        //   （月次集計バッチ INVMONTH で更新）
        SH_M01 = I_SHP_M01;
        SH_M02 = I_SHP_M02;
        SH_M03 = I_SHP_M03;

        // 加重平均（直近を重視）
        W_AVGSUU = (SH_M01 * 3 + SH_M02 * 2 + SH_M03 * 1) / 6;

        // 季節補正   ※品目カテゴリ別
        SELECT;
          WHEN W_CATCD = 'A01';  // 空調関連
            SELECT;
              WHEN W_SEASON = '07' OR W_SEASON = '08';
                W_AVGSUU *= 1.80;  // 夏季ピーク
              WHEN W_SEASON = '12' OR W_SEASON = '01';
                W_AVGSUU *= 1.50;  // 冬季
              WHEN W_SEASON = '04' OR W_SEASON = '10';
                W_AVGSUU *= 0.70;  // 端境期
            ENDSL;
          WHEN W_CATCD = 'B03';  // 建材
            IF W_SEASON >= '03' AND W_SEASON <= '05';
              W_AVGSUU *= 1.30;  // 年度始め需要
            ENDIF;
          WHEN W_CATCD = 'C07';  // 食品包装
            IF W_SEASON = '12';
              W_AVGSUU *= 2.50;  // 年末需要
            ENDIF;
            // ※2020追加 コロナ特需
            //IF %YEAR(%DATE()) = 2020;
            //  W_AVGSUU *= 1.80;
            //ENDIF;
        ENDSL;

        // 最低出庫数保証  ※ゼロ除算防止 1999追加
        IF W_AVGSUU < 1;
          W_AVGSUU = 1;
        ENDIF;
      ENDSR;

      // ===== 安全在庫計算 =====
      BEGSR CALC_SAFETY;
        W_LEADTM = IT_LEADTM;

        // リードタイム未設定の場合のデフォルト
        IF W_LEADTM = 0;
          // 仕入先別デフォルト ※ハードコード
          SELECT;
            WHEN %SUBST(IT_VENCD:1:2) = 'JP';
              W_LEADTM = 5;    // 国内
            WHEN %SUBST(IT_VENCD:1:2) = 'CN';
              W_LEADTM = 30;   // 中国
              // ※コロナ後は45日にしていたが戻した 2023
            WHEN %SUBST(IT_VENCD:1:2) = 'TW';
              W_LEADTM = 14;   // 台湾
            WHEN %SUBST(IT_VENCD:1:2) = 'US';
              W_LEADTM = 21;   // アメリカ
            OTHER;
              W_LEADTM = 14;   // その他海外
          ENDSL;
        ENDIF;

        // 安全在庫 = 平均出庫数 × √リードタイム × 安全係数
        W_ANSUU = %INT(W_AVGSUU * %SQRT(%FLOAT(W_LEADTM))
                  * W_SATEFCT);

        // 上限チェック（倉庫容量）
        // 2010追加 複数倉庫対応
        CHAIN I_WHSCD WHSMAST;
        IF %FOUND(WHSMAST);
          IF W_ANSUU > WH_MAXCAP * 0.3;
            W_ANSUU = %INT(WH_MAXCAP * 0.3);
          ENDIF;
        ENDIF;

        // ===== 以下コメントアウト 2015不具合により無効化 =====
        // // 発注点自動計算（需要予測ベース）
        // DCL-S W_FCST_QTY PACKED(9:2);
        // W_FCST_QTY = CALCFCST(W_ITEMCD:3);  // 3ヶ月予測
        // IF W_FCST_QTY > W_AVGSUU * 1.5;
        //   W_HATSUU = %INT(W_FCST_QTY * W_LEADTM / 30)
        //              + W_ANSUU;
        // ENDIF;
        // ===== コメントアウトここまで =====
      ENDSR;

      // ===== 発注データ作成 =====
      BEGSR CREATE_PO;
        LAST_PORNO += 1;
        W_PORNO = LAST_PORNO;
        OUT PORNODS;

        // 発注数計算（ロット単位に切り上げ）
        W_LOTQTY = IT_LOTQTY;
        IF W_LOTQTY <= 0;
          W_LOTQTY = 1;
        ENDIF;

        W_ORDQTY = W_HATSUU - W_YUKSUU + W_ANSUU;

        // ロット単位切り上げ
        IF %REM(W_ORDQTY:W_LOTQTY) <> 0;
          W_ORDQTY = ((%INT(W_ORDQTY / W_LOTQTY)) + 1) * W_LOTQTY;
        ENDIF;

        // 最小発注数チェック
        IF W_ORDQTY < IT_MINORD;
          W_ORDQTY = IT_MINORD;
        ENDIF;

        // 最大発注数チェック  ※予算制限 2002追加
        IF W_ORDQTY * IT_STDCOST > 5000000;  // 500万円上限
          W_ORDQTY = %INT(5000000 / IT_STDCOST);
          // ロット単位に再調整
          W_ORDQTY = (%INT(W_ORDQTY / W_LOTQTY)) * W_LOTQTY;
        ENDIF;

        // 発注データ書込み
        PO_PORNO   = %EDITC(W_PORNO:'X');
        PO_ITEMCD  = W_ITEMCD;
        PO_QTY     = W_ORDQTY;
        PO_VENCD   = IT_VENCD;
        PO_ORDDT   = %DEC(%DATE():*ISO);
        PO_DLVDT   = %DEC(%DATE() + %DAYS(W_LEADTM):*ISO);
        PO_WHSCD   = I_WHSCD;
        PO_STATUS  = '01';  // 01:発注依頼
        PO_LOTQTY  = W_LOTQTY;
        PO_UPRICE  = IT_STDCOST;
        PO_AMT     = W_ORDQTY * IT_STDCOST;
        WRITE PORREC;

        W_PORCNT += 1;
        EXSR PRT_PO;

        IN PORNODS;
      ENDSR;

      // ===== 在庫履歴出力 =====
      BEGSR WRITE_HIST;
        IH_ITEMCD  = W_ITEMCD;
        IH_HSTDATE = %DEC(%DATE():*ISO);
        IH_STKSUU  = W_STKSUU;
        IH_HIKISUU = W_HIKISUU;
        IH_YUKSUU  = W_YUKSUU;
        IH_ANSUU   = W_ANSUU;
        IH_HATSUU  = W_HATSUU;
        IH_AVGSUU  = W_AVGSUU;
        WRITE IHSTREC;
      ENDSR;

      // ===== 帳票ヘッダ出力 =====
      BEGSR PRT_HEADER;
        // 省略（帳票フォーマット）
      ENDSR;

      // ===== 帳票エラー出力 =====
      BEGSR PRT_ERR;
        // 省略
      ENDSR;

      // ===== ロット警告出力 =====
      BEGSR PRT_LOTWARN;
        // 省略
      ENDSR;

      // ===== ロット期限切れ出力 =====
      BEGSR PRT_LOTEXP;
        // 省略
      ENDSR;

      // ===== 発注データ出力 =====
      BEGSR PRT_PO;
        // 省略
      ENDSR;

      // ===== 帳票サマリ出力 =====
      BEGSR PRT_SUMMARY;
        // 省略
      ENDSR;

      // ===== バッチ終了処理 =====
      BEGSR END_BATCH;
        // ジョブログ出力
        DCL-PR QCMDEXC EXTPGM;
          CMD CHAR(256) CONST;
          LEN PACKED(15:5) CONST;
        END-PR;
        QCMDEXC('SNDPGMMSG MSG(''INVBATCH完了 ' +
                '処理件数=' + %CHAR(W_PRCCNT) +
                ' 発注件数=' + %CHAR(W_PORCNT) +
                ' エラー=' + %CHAR(W_ERRCNT) +
                ''') TOPGMQ(*EXT)':256);
      ENDSR;
