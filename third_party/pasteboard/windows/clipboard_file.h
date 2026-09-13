#ifndef PASTEBOARD_WINDOWS_CLIPBOARD_FILE_H_
#define PASTEBOARD_WINDOWS_CLIPBOARD_FILE_H_

#include <Windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

namespace pasteboard {

inline bool ReadClipboardFile(HDROP drop, UINT index, std::wstring* filename) {
  // длинные пути windows разрешены, но объём выделения из данных буфера ограничен
  constexpr UINT kMaxPathCharacters = 32767;
  const UINT length = DragQueryFileW(drop, index, nullptr, 0);
  if (length == 0 || length > kMaxPathCharacters) {
    return false;
  }

  // длины считаются в символах; лишний символ позволяет заметить рост между запросом размера и копированием
  std::vector<wchar_t> buffer(length + 2, L'\0');
  const UINT copied = DragQueryFileW(drop, index, buffer.data(), length + 2);
  if (copied != length || buffer[length] != L'\0') {
    return false;
  }
  filename->assign(buffer.data(), length);
  return true;
}

}  

#endif  
