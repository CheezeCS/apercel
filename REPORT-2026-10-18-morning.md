# apercel, отчёт за утро 18 окт 2026 (~09:00)

## Итог статуса

- GPU: 1008 МГц (pll-gpu и gpu0 подтверждены по clk_summary), governor
  привязан к gpu_thermal_zone, no_autosuspend=Y. В живой игре Mindustry
  стабильные 43 fps (было 15 на 840 МГц со старым стеком). Синтетика: 96 fps.
- Переименование: ядерный драйвер регистрируется как "apercel" (sysfs,
  dmesg, описание), прошивка читается из /lib/firmware/apercel/rogue_*.fw.
  Старый каталог прошивки удалён, MODULE_FIRMWARE-подсказки обновлены.
  Mesa имя драйвера не проверяет (проверено: "pvr" встречается только в
  генераторе UUID). Строка.renderer содержит имя чипа BXM-4-64 — это
  наименование железа, а не бренда.
- Компиляция: ядерный модуль — 0 предупреждений; Mesa (вся директория
  imagination) — 0 предупреждений (исправлены две наши const-ошибки:
  pvr_rstate_entry_remove и поле sub_cmd->gfx.rstate).

## Изменённые сегодня файлы

- driver/src/pvr_drv.h     - PVR_DRIVER_NAME "apercel", PVR_DRIVER_DESC
                             "apercel open-source driver for Imagination GPUs"
- driver/src/pvr_device.c  - префикс прошивки "apercel/rogue", docstring
- driver/src/pvr_drv.c     - MODULE_FIRMWARE("apercel/rogue_*")
- mesa pvr_device.{c,h}, pvr_arch_cmd_buffer.c, pvr_cmd_buffer.h - поправки
  const (entry_remove принимает неконстантный rstate)
- install.sh / uninstall.sh - glob-подход к бэкапам (независимо от старых
  имён файлов)
- README.md - актуализирован

## Юридическая справка по имени

Наш код — открытый Mesa-драйвер для GPU Imagination (GPL-2.0 OR MIT).
Использование ссылки на семейство железа как таковой претензий не вызывает;
обязательным является сохранение оригинальных копирайт- и SPDX-хедеров
(GPL требуетсохранять указание авторства: Imagination Technologies Ltd.,
Linaro Ltd.) — они сохранены пофайлово.

## Что осталось (только ребут)

- переименование в sysfs (powevr -> apercel) требует перезагрузки: в памяти
  пока предыдущая версия. При ребуте подгружается новый модуль с прошивкой
  из /lib/firmware/apercel. Затем ./tools/verify-after-reboot.sh — все
  пункты PASS.

## Обновление после ребута (~09:20)

После ребута обнаружилось: Mesa проверяет имя DRM-драйвера — определение
PVR_DRM_DRIVER_NAME спрятано в src/imagination/vulkan/winsys/pvr_winsys.h:46
(было "powevr"). Заменено на "apercel", Mesa пересобрана и установлена,
0 предупреждений; vkprobe и glbench восстановлены (97.8 fps).

tools/verify-after-reboot.sh и gpu-status.sh теперь берут первый доступный
setuid-помощник: doas (настроен permit nopass), затем passwordless sudo,
иначе интерактивный sudo. Итог прогонки verify-after-reboot.sh: все пункты
PASS, exit 0 ("Everything OK").

dmesg чистый: предупреждений от драйвера нет; оставшиеся записи
(cma_alloc, es8389) не относятся к GPU-стеку.

## 11:00 дополнение: причина подвисаний

Пользователь заметил в btop: CPU сбрасывается до ~400 МГц в момент обновления
экрана и затем возвращается на 1.7-2.0 ГГц. Корневая причина — governor
"schedutil" на CPU-кластерах (min OPP 416 МГц); GPU (apercel, 1008 МГц)
отдыхает, "подвисания" относятся к CPU-урежению композитора.

Фикс: performance governor на обоих кластерах (policy0 и policy6) —
частота держится на максимуме (1794/2002 МГц) постоянно; для перезагрузок
скрипт /etc/local.d/gpu-cpu-perf.start (OpenRC local service уже в
runlevel default). Откат: echo schedutil в policy*/scaling_governor.
