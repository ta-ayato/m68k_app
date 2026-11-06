***************************************************************
** stop_watch.s : ストップウォッチ・ラップ機能 ユーザプログラム (Step 10)
**   キー割り当て:
**     Space : スタート / ストップ（トグル）
**     l     : ラップ記録
**     r     : リセット
***************************************************************

.section .text
.even

* システムコール番号の定義 (os_defs.s と一致させる)
.equ SYSCALL_NUM_GETSTRING,   1
.equ SYSCALL_NUM_PUTSTRING,   2
.equ SYSCALL_NUM_RESET_TIMER, 3
.equ SYSCALL_NUM_SET_TIMER,   4

***************************************************************
** MAIN : ユーザプログラムのエントリポイント
***************************************************************
MAIN:
    * ユーザモード（%SR = 0x0000, レベル0）へ移行し、ユーザスタックを設定
    move.w  #0x0000, %SR
    lea.l   USR_STK_TOP, %SP

    * 初期表示・変数の初期化
    bsr     RESET_ALL_VALS
    bsr     UPDATE_DISPLAY

    * タイマーの停止（念のため）
    move.l  #SYSCALL_NUM_RESET_TIMER, %D0
    trap    #0

    * タイマーの設定: 1msごと (10 * 0.1ms = 10) に TIMER_TASK を呼ぶ
    move.l  #SYSCALL_NUM_SET_TIMER, %D0
    move.w  #10, %D1                | t = 10 (1ms)
    move.l  #TIMER_TASK, %D2        | コールバック関数
    trap    #0

***************************************************************
** KEY_LOOP : キー入力の常時ポーリング監視ループ
***************************************************************
KEY_LOOP:
    * 1文字取得を試みる (GETSTRING)
    move.l  #SYSCALL_NUM_GETSTRING, %D0
    move.l  #0,   %D1               | ch = 0 (UART1)
    move.l  #INP_BUF, %D2           | 読み込み先バッファ
    move.l  #1,   %D3               | size = 1
    trap    #0

    * D0 に取得した文字数が返る (0なら入力なし)
    cmpi.l  #0, %D0
    beq     KEY_LOOP

    * 入力された文字を判定
    move.b  INP_BUF, %D1
    
    * Space キー (0x20): スタート / ストップ切替
    cmpi.b  #0x20, %D1
    beq     TOGGLE_RUN

    * 'l' キー (0x6C): ラップ記録
    cmpi.b  #0x6C, %D1
    beq     RECORD_LAP

    * 'r' キー (0x72): リセット
    cmpi.b  #0x72, %D1
    beq     DO_RESET

    bra     KEY_LOOP

* --- キー処理サブルーチン ---
TOGGLE_RUN:
    not.w   RUN_FLAG                | RUN_FLAG を反転 (0 <-> -1)
    bra     KEY_LOOP

RECORD_LAP:
    * 現在の時間をラップタイムにコピー
    move.w  MIN_VAL, LAP_MIN
    move.w  SEC_VAL, LAP_SEC
    
    * ターミナルへラップタイムを出力 (Lap X: mm:ss)
    bsr     PRINT_LAP_MSG
    * LED 下位4文字を更新
    bsr     UPDATE_LED_LAP
    bra     KEY_LOOP

DO_RESET:
    bsr     RESET_ALL_VALS
    bsr     UPDATE_DISPLAY
    bra     KEY_LOOP


***************************************************************
** TIMER_TASK : タイマー割り込みタスク (1ms ごとに呼び出される)
***************************************************************
TIMER_TASK:
    movem.l %D0-%D7/%A0-%A6, -(%SP)

    * 計測中かチェック (RUN_FLAG が 0 でなければ計測中)
    tst.w   RUN_FLAG
    beq     TIMER_TASK_END

    * 1ms 経過を加算
    addi.w  #1, MS_CNT
    cmpi.w  #1000, MS_CNT           | 1000ms = 1秒
    bne     TIMER_TASK_END

    * 1秒経過時の処理
    move.w  #0, MS_CNT
    addi.w  #1, SEC_VAL
    move.w  #1, SEC_UPDATED_FLAG    | 秒が更新されたことをフラグで通知

    cmpi.w  #60, SEC_VAL
    bne     CHECK_DISP_UPDATE
    move.w  #0, SEC_VAL
    addi.w  #1, MIN_VAL
    cmpi.w  #100, MIN_VAL
    bne     CHECK_DISP_UPDATE
    move.w  #0, MIN_VAL             | 100分で 0 にラップ

CHECK_DISP_UPDATE:
    * 画面および LED の更新（秒が変わったタイミングでのみ実行）
    bsr     UPDATE_DISPLAY

TIMER_TASK_END:
    movem.l (%SP)+, %D0-%D7/%A0-%A6
    rts


***************************************************************
** 補助サブルーチン群
***************************************************************

* 全変数のリセット
RESET_ALL_VALS:
    move.w  #0, RUN_FLAG
    move.w  #0, MS_CNT
    move.w  #0, SEC_VAL
    move.w  #0, MIN_VAL
    move.w  #0, LAP_MIN
    move.w  #0, LAP_SEC
    rts

* 画面（ターミナル & LED）の更新
UPDATE_DISPLAY:
    movem.l %D0-%D3/%A0-%A1, -(%SP)
    
    * mm:ss 文字列を生成してバッファへ格納
    bsr     FORMAT_TIME_STR
    
    * ターミナルへ出力 (キャリッジリターン付きで1行更新、またはシンプル出力)
    move.l  #SYSCALL_NUM_PUTSTRING, %D0
    move.l  #0,   %D1
    move.l  #TIME_MSG, %D2
    move.l  #7,   %D3               | "mm:ss\r\n" の長さ
    trap    #0

    * LED 上位4文字 (`LED7`〜`LED4`) に現在の計測タイムを表示
    move.b  TIME_MSG+0, LED7
    move.b  TIME_MSG+1, LED6
    move.b  TIME_MSG+2, LED5
    move.b  TIME_MSG+3, LED4

    movem.l (%SP)+, %D0-%D3/%A0-%A1
    rts

* 数値から "mm:ss\r\n" 文字列を作る簡易変換
FORMAT_TIME_STR:
    * 分の十の位・一の位
    move.w  MIN_VAL, %D0
    ext.l   %D0
    divu    #10, %D0                | 余り(下位16bit)=一の位, 商(上位16bit)=十の位
    move.l  %D0, %D1
    swap    %D1
    addi.b  #'0', %D0
    move.b  %D0, TIME_MSG+0
    addi.b  #'0', %D1
    move.b  %D1, TIME_MSG+1

    move.b  #':', TIME_MSG+2

    * 秒の十の位・一の位
    move.w  SEC_VAL, %D0
    ext.l   %D0
    divu    #10, %D0
    move.l  %D0, %D1
    swap    %D1
    addi.b  #'0', %D0
    move.b  %D0, TIME_MSG+3
    addi.b  #'0', %D1
    move.b  %D1, TIME_MSG+4

    move.b  #0x0D, TIME_MSG+5       | \r
    move.b  #0x0A, TIME_MSG+6       | \n
    rts

* ラップタイムをターミナルに表示する
PRINT_LAP_MSG:
    * ラップタイム文字列を作成 (簡易的に LAP_MSG に埋め込む)
    move.w  LAP_MIN, %D0
    ext.l   %D0
    divu    #10, %D0
    move.l  %D0, %D1
    swap    %D1
    addi.b  #'0', %D0
    move.b  %D0, LAP_MSG+5
    addi.b  #'0', %D1
    move.b  %D1, LAP_MSG+6

    move.w  LAP_SEC, %D0
    ext.l   %D0
    divu    #10, %D0
    move.l  %D0, %D1
    swap    %D1
    addi.b  #'0', %D0
    move.b  %D0, LAP_MSG+8
    addi.b  #'0', %D1
    move.b  %D1, LAP_MSG+9

    move.l  #SYSCALL_NUM_PUTSTRING, %D0
    move.l  #0,   %D1
    move.l  #LAP_MSG, %D2
    move.l  #14,  %D3
    trap    #0
    rts

* LED 下位4文字 (`LED3`〜`LED0`) にラップタイムを表示
UPDATE_LED_LAP:
    move.b  LAP_MSG+5, LED3
    move.b  LAP_MSG+6, LED2
    move.b  LAP_MSG+7, LED1         | ':'
    move.b  LAP_MSG+8, LED0
    rts


***************************************************************
** データ領域
***************************************************************
.section .data
.even
TIME_MSG:
    .ascii  "00:00\r\n"
    .even
LAP_MSG:
    .ascii  "Lap: 00:00\r\n"
    .even

***************************************************************
** BSS領域（変数・スタック）
***************************************************************
.section .bss
.even
RUN_FLAG:       .ds.w   1           | 0:停止, 1:計測中
MS_CNT:         .ds.w   1           | ミリ秒カウンタ (0〜999)
SEC_VAL:        .ds.w   1           | 秒 (0〜59)
MIN_VAL:        .ds.w   1           | 分 (0〜99)
LAP_MIN:        .ds.w   1           | ラップ 分
LAP_SEC:        .ds.w   1           | ラップ 秒
SEC_UPDATED_FLAG: .ds.w 1

INP_BUF:        .ds.b   4           | キー入力用バッファ
.even
USR_STK:
    .ds.b   0x4000
.even
USR_STK_TOP: