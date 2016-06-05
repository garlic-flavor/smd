/** port.d
 * Date:       2016-Jun-05 17:19:21
 * Dmd:        2.071.0
 * Authors:    KUMA
 * License:    CC0
 */
module sworks.win32.port;
/// Win32api porting by http://www.dsource.org/projects/bindings/wiki/WindowsApi
/// win32.lib/win64.lib をリンクして使う。
public import core.sys.windows.windows;
//pragma(lib,"lib\\win32.lib");
pragma(lib,"gdi32.lib");
pragma(lib, "User32.lib");

version (Unicode){}
else {pragma(msg,"port : support only Unicode version."); }

alias WM_MOUSEHWHEEL = core.sys.windows.winuser.WM_MOUSEHWHEEL;
// 定義の追加
enum MOUSEEVENTF_XDOWN = 128;
enum MOUSEEVENTF_XUP = 256;
enum MOUSEEVENTF_HWHEEL = 4096;
enum LLMHF_INJECTED = 0x00000001;
enum XBUTTON1 = 1;
enum XBUTTON2 = 2;
//enum WM_MOUSEHWHEEL = 0x020e;
enum LBS_COMBOBOX = 0x8000;

enum FOF_NO_UI = FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOCONFIRMMKDIR | FOF_NOERRORUI;

/*
void ZeroMemory(void* Destination, size_t Length)
{
    (cast(byte*)Destination)[0..Length] = 0;
}
*/
