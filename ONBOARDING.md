# AIImageEditor — онбординг: установка и работа через AI-агента

AIImageEditor — macOS-редактор скриншотов для App Store: композиция картинок,
текст, девайс-безели, градиенты, блюры, тени, экспорт PNG под размеры App Store.
Главная фишка — приложением может пользоваться **AI-агент напрямую** (Claude
Code, Claude Desktop, Cursor, Codex CLI и любой другой MCP-клиент): вы описываете
скриншот словами, агент собирает его командами и сам видит результат рендера.

Ниже — путь от нуля до «агент рендерит скриншоты по промпту» за ~10 минут.

---

## 1. Требования

- macOS 14+
- Xcode 15+ (с командной строкой: `xcode-select --install`)
- [Tuist](https://tuist.io): `brew install tuist`

## 2. Установка

```bash
# 1. Клонировать репозиторий
git clone git@github.com:mbulatIT/renderIt.git AIImageEditor
cd AIImageEditor

# 2. Сгенерировать Xcode-проект
tuist generate

# 3. Собрать CLI и MCP-сервер
xcodebuild -workspace AIImageEditor.xcworkspace \
           -scheme aiimageeditor-cli -configuration Release \
           -derivedDataPath Derived build
xcodebuild -workspace AIImageEditor.xcworkspace \
           -scheme aiimageeditor-mcp -configuration Release \
           -derivedDataPath Derived build

# 4. Положить бинари на $PATH
#    (Xcode заменяет дефисы на подчёркивания в именах файлов — это не ошибка)
sudo cp Derived/Build/Products/Release/aiimageeditor_cli /usr/local/bin/aiimageeditor-cli
sudo cp Derived/Build/Products/Release/aiimageeditor_mcp /usr/local/bin/aiimageeditor-mcp
```

Опционально — GUI-приложение (обычный SwiftUI-редактор для ручной доводки):

```bash
xcodebuild -workspace AIImageEditor.xcworkspace \
           -scheme AIImageEditor -configuration Release \
           -derivedDataPath Derived build
open Derived/Build/Products/Release/AIImageEditor.app
```

GUI, CLI и MCP работают с одним и тем же JSON-файлом `.aiproj` — можно начать
проект агентом, а докрутить руками в GUI (и наоборот).

## 3. Подключить к AI-агенту (главный шаг)

### Claude Code

```bash
claude mcp add aiimageeditor /usr/local/bin/aiimageeditor-mcp
claude mcp list   # должен показать "aiimageeditor"
```

### Claude Desktop

В `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "aiimageeditor": {
      "command": "/usr/local/bin/aiimageeditor-mcp",
      "args": []
    }
  }
}
```

Перезапустить Claude Desktop — тулы появятся с префиксом `aiimageeditor.`.

### Cursor / Codex CLI / Gemini CLI / Cline / Continue

Аналогичный блок конфига для каждого инструмента — готовые сниппеты в
[README.md → «Setup guide — AI coding tools»](README.md#setup-guide--ai-coding-tools-cli).

### Проверка

Попросите агента: *«перечисли тулы aiimageeditor»* — должно быть ~30 команд
(`new`, `add_text`, `add_bezel`, `add_gradient`, `render`, …). Либо руками:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"smoke","version":"0"}}}' \
  | aiimageeditor-mcp
```

## 4. Как пользоваться через агента

Просто описываете результат — агент сам создаёт проект, ставит слои и рендерит.
Тул `render` возвращает PNG прямо в чат, поэтому агент **видит** свой результат
и сам исправляет огрехи. Примеры промптов:

> «Создай проект под iPhone 6.7" в `~/screens/release.aiproj`. Возьми скриншоты
> из `~/screens/captures/`, оберни каждый в безель iPhone 17 Pro, сверху
> заголовок белым болдом 110pt, фон — тёмный градиент. Отрендери в `~/screens/out/`.»

> «Сделай тёмный фон с линейным градиентом #0A0F2A → #1B2A6B, скриншот в безеле
> по центру с тенью, под ним подпись 60pt серым.»

> «Открой `hero.aiproj`, подними заголовок на 80px выше, скругли углы карточки
> в стиле squircle и перерендери.»

Что умеет движок (агент знает это из схем тулов):

- **Безели**: iPhone 17 Pro / Pro Max / SE, iPad Pro 13"/11" (вкл. M4),
  MacBook 14"/16" — скриншот автоматически вписывается в экран.
- **Слои**: текст, картинки, прямоугольники, эллипсы, линии со стрелками,
  многоугольники, звёзды, градиенты (linear/radial), gaussian-блюры
  (в т.ч. переменной силы — «tilt-shift»).
- **Оформление**: тени, скругления (squircle / arc / chamfer, по отдельным
  углам), градиентная заливка текста и фигур, blend modes, поворот, прозрачность,
  группы с обрезкой.
- **Пресеты App Store**: iPhone 6.7"/6.5", iPad Pro 13"/12.9", Mac, Watch Ultra.
- **Мультистраничные проекты** с несколькими превью — один PNG на превью.

Сервер stateless: каждый вызов читает и пишет `.aiproj` на диск, так что файл
можно параллельно открывать в GUI или править руками — рассинхрона не будет.

## 5. CLI без агента (скрипты, CI)

```bash
aiimageeditor-cli new --preset iphone-6.7 --output hero.aiproj
aiimageeditor-cli add-bezel --project hero.aiproj \
    --device iphone17Pro --asset-path screens/home.png --at center
aiimageeditor-cli add-text --project hero.aiproj \
    --text "Edit photos with AI" \
    --font-size 110 --font-weight bold --color "#FFFFFF" --at top-center
aiimageeditor-cli render --project hero.aiproj --output hero.png
```

## 6. Куда смотреть дальше

| Документ | Зачем |
|---|---|
| [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md) | Все команды CLI/MCP с аргументами и примерами |
| [docs/MCP_GUIDE.md](docs/MCP_GUIDE.md) | Детали протокола MCP и регистрация сервера |
| [docs/PUBLISHING.md](docs/PUBLISHING.md) | Подписанная дистрибуция: DMG с нотаризацией (без Xcode у получателя) |
| [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) | Полная схема `.aiproj` JSON |
| [docs/DEVICE_BEZELS.md](docs/DEVICE_BEZELS.md) | Список безелей и их геометрия |
| [docs/PRESETS.md](docs/PRESETS.md) | Размеры скриншотов App Store |
| [docs/EXAMPLES.md](docs/EXAMPLES.md) | Готовые примеры проектов |
