/* =========================================================
 * 8051 / STC8 椤圭洰 涓撶敤锛歈4 (SFR 鍒嗛〉) + Q5 (16/32 浣嶉潪鍘熷瓙)
 *           鍧忎緥 + 濂戒緥 娴嬭瘯
 * 鐢?sfr / sbit / #include <STC8.h> 璁?Q4 妫€娴嬪櫒璇嗗埆涓?8051 椤圭洰
 * ========================================================= */
#include <STC8.h>
#include <stdint.h>

/* ======== Q5 鍏ㄥ眬瀹藉彉閲忥紙16/32 浣嶏級澹版槑 ======== */

/* 鉂?Q5-1 32 浣嶅叏灞€鍙橀噺锛屽湪 main 閲岃璇伙紝浣嗛檮杩戞棤 EA=0 淇濇姢 鈥斺€?搴旀姤璀?*/
uint32_t g_systick_ms;

/* 鉂?Q5-2 16 浣嶇幆褰㈢紦鍐插啓鎸囬拡锛圛SR 涓細鏀癸級鈥斺€?涓诲惊鐜鏃舵病鍏充腑鏂?鈥斺€?搴旀姤璀?*/
volatile unsigned short g_tick_count;

/* 鉂?Q5-3 32 浣嶈剦鍐茬疮鍔犲櫒锛堝畾鏃跺櫒 ISR 姣忔 +1锛夆€斺€?涓诲惊鐜娌?EA=0 鈥斺€?搴旀姤璀?*/
unsigned long g_pulse_cnt;

/* ======== Q4 椤靛垏鎹㈢█鐤忥紙pdata 鎸囬拡鑷璺ㄩ〉锛?======= */

unsigned char pdata *g_pdata_buf;   /* pdata = 鍒嗛〉闂存帴璁块棶 256 瀛楄妭 * 256 椤碉紝P2 涓洪〉瀵勫瓨鍣?*/
extern unsigned char rcvbyte(void);

/* 鉂?Q4-1 MOVX @R0/@R1 鑷寰幆璇?300 瀛楄妭锛屼絾浠庢湭鍐?P2 瀵勫瓨鍣? *        鈥斺€?璺?256 瀛楄妭椤佃竟鐣屾椂 P2 娌″垏锛岃鍒伴敊璇〉 鈥斺€?搴旀姤璀︼紙涓や釜鍚彂寮忛兘搴斿懡涓級
 */
void pdata_bad_read_257(void)
{
    unsigned short i;
    unsigned char sum;
    for (i = 0; i < 300; i++) {
        /* 鍐呭祵姹囩紪椋庢牸鐨?MOVX @R0 璇?pdata锛汣 灞傚 pdata 鎸囬拡璧嬪€煎睍寮€灏辨槸 MOV R0,<浣庡瓧鑺?; MOVX A,@R0
           杩欓噷鏄惧紡鍐?__asm MOVX 浠ヤ究 Q4 妫€娴嬫崟鎹?*/
        sum += g_pdata_buf[i];   /* 鈫?C 灞?pdata[i] 瀹為檯灞曞紑涓?MOVX @R0/@R1 */
        __asm
            MOV R0, g_pdata_buf
            MOVX A, @R0          /* 鈫?杩欐潯鏄湡姝ｇ殑 MOVX @R0锛孮4 妫€娴嬪櫒瑕佹姄 */
        __endasm;
    }
    /* 鏁翠釜鍑芥暟浠庡ご鍒板熬娌℃湁 P2 = 銆丳DATA_BANK = 銆丼ETB RS1 / CLR RS1 */
}

/* 鉁?Q4-2 濂戒緥锛氬惊鐜瘡鍒?256 杈圭晫灏卞啓 P2 鍒囬〉 鈥斺€?涓嶅簲鎶ヨ"椤靛垏鎹㈢█鐤? */
void pdata_good_read_257(void)
{
    unsigned short i;
    unsigned char sum;
    P2 = 0x10;   /* 鍏堟妸璧峰椤靛瘎瀛樺櫒 P2 鍐欏埌姝ｇ‘椤碉細0x10xx 椤?*/
    for (i = 0; i < 300; i++) {
        if ((i & 0xFF) == 0) {
            P2 = 0x10 + (unsigned char)(i >> 8);   /* 鈫?璺ㄩ〉鍒?P2 */
        }
        sum += g_pdata_buf[i];
    }
}

/* ======== Q5 璇诲鍙橀噺鏃?EA=0 淇濇姢 ======== */

/* ISR 涓敼鍐欏鍙橀噺锛堣妫€娴嬪櫒"鐭ラ亾"杩欎釜鍙橀噺鍦?ISR 琚啓锛?鈥斺€?杩欓噷鍙槸涓轰簡璁╁潖渚嬪悎鐞嗭紝瀹為檯鑷姩鍖栨棤娉曞畬鍏ㄨ法鍑芥暟杩借釜锛?   浣?Q5 鐨勫惎鍙戝紡鏄細**鍙鏄?16/32 浣嶅叏灞€鍙橀噺锛屽湪 8051 椤圭洰閲岃瀹冮兘搴旇鏈夊叧涓柇**锛堝畞鏉€閿欎笉鏀捐繃锛?*/
void timer0_isr(void) __interrupt(1)
{
    g_systick_ms++;
    g_tick_count++;
    g_pulse_cnt += 3;
}

/* 鉂?Q5-4 鍧忎緥锛氫富寰幆閲岀洿鎺ヨ g_systick_ms / g_tick_count / g_pulse_cnt锛屾病 EA=0 鈥斺€?涓変釜閮芥姤璀?*/
void bad_main_read(void)
{
    unsigned char tmp;
    if (g_systick_ms > 1000UL) {    /* 鈫?32 浣嶈 4 瀛楄妭锛屽崐鏇存柊鏋佸父瑙?*/
        tmp = 1;
    }
    while (g_tick_count < 100) {    /* 鈫?16 浣嶈 2 瀛楄妭 */
        /* wait */
    }
    if (g_pulse_cnt > 0x10000) {    /* 鈫?32 浣嶆棤绗﹀彿 */
        tmp = 2;
    }
}

/* 鉁?Q5-5 濂戒緥锛氬叧涓柇鍚庤銆佸紑涓柇鍚庢仮澶?鈥斺€?涓嶅簲鎶ヨ锛堝墠鍚?5 琛屾湁 EA=0/EA=1锛?*/
void good_main_read(void)
{
    uint32_t ms;
    unsigned short tk;
    unsigned long pc;

    EA = 0;
    ms = g_systick_ms;
    tk = g_tick_count;
    pc = g_pulse_cnt;
    EA = 1;

    if (ms > 1000UL) {
        /* ... */
    }
    if (tk < 100) {
        /* ... */
    }
    if (pc > 0x10000) {
        /* ... */
    }
}

/* 鉁?Q5-6 鍙︿竴绉嶅ソ渚嬶細ENTER_CRITICAL / EXIT_CRITICAL 鈥斺€?鍚屾牱涓嶅湪 5 琛屽唴鍏充腑鏂氨涓嶆姤璀?*/
void good_main_read2(void)
{
    uint32_t ms;
    ENTER_CRITICAL();
    ms = g_systick_ms;
    EXIT_CRITICAL();
    (void)ms;
}
