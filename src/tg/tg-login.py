#!/usr/bin/env python3
"""Midnight Pulse · one-time Telegram login for the chat widget.

1. Get api_id / api_hash at https://my.telegram.org → API development tools (any app name).
2. Run this in a terminal:  midnight-pulse-tg-login        (QR login, recommended)
                            midnight-pulse-tg-login --code (classic phone + code)
3. QR: on your phone open Telegram → Settings → Devices → Link Desktop Device and scan.
   Enter your 2FA password here if you have one.
4. Pick the chat to show in the widget.
Everything is stored only on this computer, readable only by you.
"""
import asyncio, getpass, json, os, subprocess, sys
from pathlib import Path

from telethon import TelegramClient, errors
from telethon.tl.types import User

H = Path.home()
CFG = H / '.config/midnight-pulse/tg.json'
DATA = H / '.local/share/midnight-pulse/tg'
QR_PNG = DATA / 'login-qr.png'


def ask(prompt, default=''):
    v = input(f'{prompt}{f" [{default}]" if default else ""}: ').strip()
    return v or default


def lock_down():
    for f in DATA.glob('*'):
        os.chmod(f, 0o600)


def show_qr(url, first):
    import qrcode
    qr = qrcode.QRCode(border=2)
    qr.add_data(url)
    qr.make(fit=True)
    print('\033[2J\033[H' if not first else '', end='')
    print('Отсканируй телефоном: Telegram → Настройки → Устройства → Подключить устройство\n')
    qr.print_ascii(invert=True)
    img = qr.make_image(fill_color='#0D1630', back_color='white').resize((420, 420))
    img.save(QR_PNG)
    os.chmod(QR_PNG, 0o600)
    print('\n(QR также открыт отдельным окном; он обновляется сам каждые ~25 с)')


async def qr_login(client):
    viewer = None
    first = True
    while True:
        qr = await client.qr_login()
        show_qr(qr.url, first)
        if first:
            viewer = subprocess.Popen(['gwenview', str(QR_PNG)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            first = False
        try:
            await qr.wait(timeout=25)
            break
        except asyncio.TimeoutError:
            continue                          # token expired → fresh QR
        except errors.SessionPasswordNeededError:
            if viewer:
                viewer.terminate()
            await client.sign_in(password=getpass.getpass('\nПароль 2FA (облачный пароль, не отображается): '))
            break
    if viewer and viewer.poll() is None:
        viewer.terminate()
    QR_PNG.unlink(missing_ok=True)


async def code_login(client):
    await client.start(phone=lambda: ask('Номер телефона (+…)'),
                       code_callback=lambda: ask('Код (пришёл в чат «Telegram» в приложении)'),
                       password=lambda: getpass.getpass('Пароль 2FA (если есть): '))


async def main():
    old = json.loads(CFG.read_text()) if CFG.exists() else {}
    print('\n✦ Midnight Pulse · вход в Telegram для виджета чата\n')
    if not old.get('api_id'):
        print('Ключи берутся на https://my.telegram.org → API development tools\n')
    api_id = ask('api_id', str(old.get('api_id', '')))
    if old.get('api_hash'):
        api_hash = getpass.getpass('api_hash (Enter — оставить прежний): ').strip() or old['api_hash']
    else:
        api_hash = getpass.getpass('api_hash (ввод не отображается): ').strip()

    DATA.mkdir(parents=True, exist_ok=True)
    os.chmod(DATA, 0o700)
    subprocess.run(['systemctl', '--user', 'stop', 'midnight-pulse-tg'], capture_output=True)
    client = TelegramClient(str(DATA / 'widget'), int(api_id), api_hash,
                            device_model='Midnight Pulse widget', system_version='KDE Plasma', app_version='1.0')
    await client.connect()
    if not await client.is_user_authorized():
        if '--code' in sys.argv:
            await code_login(client)
        else:
            await qr_login(client)
    lock_down()
    me = await client.get_me()
    print(f'\n✓ Вошёл как {me.first_name}\n\nНедавние личные чаты:')
    people = []
    async for d in client.iter_dialogs(limit=80):
        if isinstance(d.entity, User) and not d.entity.bot and not d.entity.is_self:
            people.append(d)
            print(f'  {len(people):2d}. {d.name}' + (f'  (@{d.entity.username})' if d.entity.username else ''))
            if len(people) >= 20:
                break
    pick = ask('\nНомер чата для виджета', '1')
    chosen = people[int(pick) - 1]
    CFG.parent.mkdir(parents=True, exist_ok=True)
    CFG.write_text(json.dumps({'api_id': int(api_id), 'api_hash': api_hash, 'peer': chosen.entity.id}, indent=2))
    os.chmod(CFG, 0o600)
    await client.disconnect()
    lock_down()
    subprocess.run(['systemctl', '--user', 'enable', '--now', 'midnight-pulse-tg'], capture_output=True)
    subprocess.run(['systemctl', '--user', 'restart', 'midnight-pulse-tg'], capture_output=True)
    print(f'\n💙 Готово! Виджет показывает чат с «{chosen.name}».\n')


if __name__ == '__main__':
    asyncio.run(main())
