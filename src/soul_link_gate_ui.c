#include "soul_link_gate_ui.h"

#include "constants/charcode.h"
#include "constants/graphics.h"
#include "bg_window.h"
#include "brightness_controller.h"
#include "font.h"
#include "gx_layers.h"
#include "heap.h"
#include "main.h"
#include "render_window.h"
#include "screen_fade.h"
#include "soul_link_gate.h"
#include "string_gf.h"
#include "system.h"
#include "text.h"

static BgConfig *sBg;
static Window sWindow;
static u16 sLastStatus;
static BOOL sCancelled;

static void PrintLine(const char *text, int y)
{
    String *string = String_Init(64, HEAP_ID_GAME_START);
    while (*text) {
        char ch = *text++;
        String_AppendChar(string, ch >= 'A' && ch <= 'Z' ? CHAR_A + ch - 'A' : CHAR_SPACE);
    }
    Text_AddPrinterWithParams(&sWindow, FONT_SYSTEM, string, 0, y, TEXT_SPEED_INSTANT, NULL);
    String_Free(string);
}

void SoulLinkGateUI_Open(void)
{
    static const GXBanks banks = { GX_VRAM_BG_256_AB, GX_VRAM_BGEXTPLTT_NONE,
        GX_VRAM_SUB_BG_NONE, GX_VRAM_SUB_BGEXTPLTT_NONE, GX_VRAM_OBJ_NONE,
        GX_VRAM_OBJEXTPLTT_NONE, GX_VRAM_SUB_OBJ_NONE, GX_VRAM_SUB_OBJEXTPLTT_NONE,
        GX_VRAM_TEX_NONE, GX_VRAM_TEXPLTT_NONE };
    static const GraphicsModes modes = { GX_DISPMODE_GRAPHICS, GX_BGMODE_0, GX_BGMODE_0, GX_BG0_AS_2D };
    static const BgTemplate bg = { .bufferSize = 0x800, .screenSize = BG_SCREEN_SIZE_256x256,
        .colorMode = GX_BG_COLORMODE_16, .screenBase = GX_BG_SCRBASE_0x0000,
        .charBase = GX_BG_CHARBASE_0x18000, .bgExtPltt = GX_BG_EXTPLTT_01, .priority = 1 };
    static const WindowTemplate window = { 0, 3, 3, 26, 18, 1, 35 };
    SetVBlankCallback(NULL, NULL);
    SetHBlankCallback(NULL, NULL);
    GXLayers_DisableEngineALayers();
    GXLayers_DisableEngineBLayers();
    G2_BlendNone();
    G2S_BlendNone();
    GX_SetVisibleWnd(GX_WNDMASK_NONE);
    GXS_SetVisibleWnd(GX_WNDMASK_NONE);
    gSystem.whichScreenIs3D = DS_SCREEN_MAIN;
    GXLayers_SwapDisplay();
    GXLayers_SetBanks(&banks);
    sBg = BgConfig_New(HEAP_ID_GAME_START);
    SetAllGraphicsModes(&modes);
    Bg_InitFromTemplate(sBg, BG_LAYER_MAIN_0, &bg, 0);
    Bg_ClearTilemap(sBg, BG_LAYER_MAIN_0);
    Bg_ClearTilesRange(BG_LAYER_MAIN_0, 32, 0, HEAP_ID_GAME_START);
    Bg_MaskPalette(BG_LAYER_MAIN_0, GX_RGB(4, 4, 8));
    Bg_MaskPalette(BG_LAYER_SUB_0, GX_RGB(4, 4, 8));
    LoadStandardWindowGraphics(sBg, BG_LAYER_MAIN_0, 503, 2, 0, HEAP_ID_GAME_START);
    Font_LoadTextPalette(PAL_LOAD_MAIN_BG, PLTT_OFFSET(1), HEAP_ID_GAME_START);
    Text_ResetAllPrinters();
    Window_AddFromTemplate(sBg, &sWindow, &window);
    Window_DrawStandardFrame(&sWindow, 0, 503, 2);
    sLastStatus = 0xFFFF;
    sCancelled = FALSE;
    GXLayers_TurnBothDispOn();
    ResetScreenMasterBrightness(DS_SCREEN_MAIN);
    ResetScreenMasterBrightness(DS_SCREEN_SUB);
    BrightnessController_SetScreenBrightness(0, GX_BLEND_PLANEMASK_BG0 | GX_BLEND_PLANEMASK_BD, BRIGHTNESS_BOTH_SCREENS);
}

void SoulLinkGateUI_Update(void)
{
    u16 status = SoulLinkGate_Status();
    if (JOY_NEW(PAD_BUTTON_B) && status != SOUL_LINK_GATE_APPROVED) {
        sCancelled = TRUE;
        return;
    }
    if (JOY_NEW(PAD_BUTTON_START)) SoulLinkGate_Start();
    if (status == sLastStatus) return;
    sLastStatus = status;
    Window_FillTilemap(&sWindow, 15);
    PrintLine("SOUL LINK LOBBY", 0);
    PrintLine(status == SOUL_LINK_GATE_READY ? "ROSTER READY" :
        status == SOUL_LINK_GATE_REJECTED ? "RUN REJECTED" : "WAITING FOR PLAYERS", 32);
    PrintLine("HOST PRESS START WHEN READY", 64);
    PrintLine("CHECK LUA CONSOLE FOR DETAILS", 88);
    PrintLine("B RETURNS TO TITLE", 120);
    Window_CopyToVRAM(&sWindow);
}

BOOL SoulLinkGateUI_Cancelled(void)
{
    return sCancelled;
}

void SoulLinkGateUI_Close(void)
{
    SetScreenColorBrightness(DS_SCREEN_MAIN, COLOR_BLACK);
    SetScreenColorBrightness(DS_SCREEN_SUB, COLOR_BLACK);
    Window_Remove(&sWindow);
    Bg_ToggleLayer(BG_LAYER_MAIN_0, FALSE);
    Bg_FreeTilemapBuffer(sBg, BG_LAYER_MAIN_0);
    Heap_Free(sBg);
    sBg = NULL;
}
