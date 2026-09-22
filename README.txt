WORKSHOP SHIFT — PWA ДЛЯ РАЗМЕЩЕНИЯ

Содержимое папки:
- index.html — приложение
- manifest.webmanifest — PWA-манифест
- service-worker.js — офлайн-кэш
- config.js — настройки backend
- icon-192.png / icon-512.png — иконки

КАК РАЗМЕСТИТЬ НА NETLIFY
1. Откройте netlify.com и войдите/создайте аккаунт.
2. Выберите Add new site -> Deploy manually.
3. Перетащите всю папку workshop-shift-pwa-ready в окно загрузки.
4. После публикации Netlify выдаст HTTPS-ссылку.
5. На iPhone откройте ссылку именно в Safari.
6. Нажмите Поделиться -> На экран «Домой».

КАК РАЗМЕСТИТЬ НА GITHUB PAGES
1. Создайте новый репозиторий.
2. Загрузите все файлы из этой папки в корень репозитория.
3. Settings -> Pages -> Deploy from a branch -> main / root.
4. Откройте выданную HTTPS-ссылку в Safari.
5. Поделиться -> На экран «Домой».

ВАЖНО
Эта версия полностью работает локально на одном устройстве после размещения по HTTPS.
Данные сохраняются в localStorage браузера.
Для синхронизации между телефонами нужно подключить Supabase в config.js и добавить серверные операции. Поля уже предусмотрены:
  supabaseUrl
  supabaseAnonKey

Не помещайте в config.js секретные server/service_role ключи.
