#!/usr/bin/env python3
"""Midnight Pulse · Telegram chat daemon.

Signs into the user's own Telegram account (Telethon, like any extra Telegram device) and mirrors
exactly ONE private chat to the desktop chat widget over ws://127.0.0.1:47801/?token=…

Files (all chmod 600, never leave this machine):
  ~/.config/midnight-pulse/tg.json          api_id, api_hash, peer id   (written by tg-login.py)
  ~/.config/midnight-pulse/tg-token         random token the widget must present
  ~/.local/share/midnight-pulse/tg/*.session   Telegram session
  ~/.cache/midnight-pulse/tg/               avatar + photo/sticker thumbnails

Protocol (JSON):
  → widget  {"t":"state","state":"ok|need_login|no_config|error","msg":...}
            {"t":"peer","name","avatar","status","online"}   {"t":"history","msgs":[…]}
            {"t":"msg","m":{…}}  {"t":"edit","m":{…}}  {"t":"del","ids":[…]}
            {"t":"typing"}  {"t":"read","max":id}  {"t":"unread","n":n}
            {"t":"older","msgs":[…]}  {"t":"progress","p":0..1}  {"t":"voice","id","path"}  {"t":"stickers","items":[…]}
            {"t":"recording","on":bool,"sec":n}  {"t":"toast","text"}  {"t":"clip","files":[…]}
  ← widget  {"t":"send","text","reply"}  {"t":"send_file","path","caption","reply"}  {"t":"edit","id","text"}
            {"t":"delete","id"}  {"t":"react","id","e"}  {"t":"read"}  {"t":"typing"}  {"t":"more","before"}
            {"t":"open","id"}  {"t":"voice","id"}  {"t":"stickers"}  {"t":"send_sticker","id","reply"}
            {"t":"rec_start"}  {"t":"rec_stop","send":bool,"reply"}  {"t":"paste"} (clipboard image/files → "clip")
Messages are never marked read automatically — only when the widget asks (user hovered it).
"""
import asyncio, json, os, secrets, shutil, sys, time
from urllib.parse import unquote, urlparse
from pathlib import Path

from telethon import TelegramClient, events, functions, types
from telethon.utils import get_display_name
import websockets

H = Path.home()
CFG = H / '.config/midnight-pulse/tg.json'
TOKEN = H / '.config/midnight-pulse/tg-token'
DATA = H / '.local/share/midnight-pulse/tg'
CACHE = H / '.cache/midnight-pulse/tg'
PORT = 47801
KEEP = 40                       # messages kept in the widget
WL_PASTE = shutil.which('wl-paste') or str(H / '.local/share/midnight-pulse/bin/wl-paste')
IMAGE_TYPES = ('image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/bmp')

clients = set()
state = {'state': 'starting', 'msg': ''}
peer_info = {}
history = []                    # serialised, oldest → newest
read_out_max = 0
unread = 0
tg = None
peer = None


def private(p):
    p.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(p.parent, 0o700)
    if p.exists():
        os.chmod(p, 0o600)


def token():
    if not TOKEN.exists():
        TOKEN.parent.mkdir(parents=True, exist_ok=True)
        TOKEN.write_text(secrets.token_urlsafe(24))
    os.chmod(TOKEN, 0o600)
    return TOKEN.read_text().strip()


async def send_all(obj):
    if not clients:
        return
    data = json.dumps(obj, ensure_ascii=False)
    await asyncio.gather(*(c.send(data) for c in list(clients)), return_exceptions=True)


def set_state(s, msg=''):
    state.update(state=s, msg=msg)
    return send_all({'t': 'state', **state})


# ------------------------------------------------------------------------------- serialise
def best_thumb(sizes, target=480):
    """index of the largest PhotoSize not wider than target (Telethon's thumb= index)."""
    best, bi = -1, -1
    for i, s in enumerate(sizes or []):
        w = getattr(s, 'w', 0) or 0
        if isinstance(s, (types.PhotoSize, types.PhotoCachedSize, types.PhotoSizeProgressive)) and w <= target and w > best:
            best, bi = w, i
    return bi if bi >= 0 else -1


def cache_dir():
    CACHE.mkdir(parents=True, exist_ok=True)
    os.chmod(CACHE, 0o700)
    return CACHE


async def media_of(m):
    """→ (kind, local path, w, h, label)"""
    cache_dir()
    try:
        if m.photo:
            p = CACHE / f'p{m.id}.jpg'
            if not p.exists():
                await tg.download_media(m, file=str(p), thumb=best_thumb(m.photo.sizes))
            s = max(m.photo.sizes, key=lambda z: getattr(z, 'w', 0) or 0)
            return 'photo', str(p), getattr(s, 'w', 1), getattr(s, 'h', 1), ''
        if m.sticker:
            doc = m.document
            static = doc.mime_type == 'image/webp'
            p = CACHE / f's{doc.id}.webp'
            if not p.exists():
                if static:
                    await tg.download_media(m, file=str(p))
                elif doc.thumbs:
                    await tg.download_media(m, file=str(p), thumb=-1)
            alt = next((a.alt for a in doc.attributes if isinstance(a, types.DocumentAttributeSticker)), '')
            return 'sticker', str(p) if p.exists() else '', 160, 160, alt
        if m.gif or m.video or m.video_note:
            p = CACHE / f'v{m.id}.jpg'
            if not p.exists() and m.document.thumbs:
                await tg.download_media(m, file=str(p), thumb=-1)
            return 'video', str(p) if p.exists() else '', 320, 200, '🎬 видео' if not m.gif else 'GIF'
        if m.voice:
            d = next((a.duration for a in m.document.attributes if isinstance(a, types.DocumentAttributeAudio)), 0)
            return 'voice', '', 0, 0, f'🎤 голосовое {int(d) // 60}:{int(d) % 60:02d}'
        if m.audio:
            return 'other', '', 0, 0, '🎵 ' + (m.file.title or m.file.name or 'аудио')
        if m.document:
            return 'other', '', 0, 0, '📎 ' + (m.file.name or 'файл')
        if m.geo:
            return 'other', '', 0, 0, '📍 геолокация'
    except Exception as e:                       # media is best-effort
        print('media error', e, file=sys.stderr)
    return 'text', '', 0, 0, ''


def reactions_of(m):
    out = []
    r = getattr(m, 'reactions', None)
    for res in (r.results if r else []):
        e = getattr(res.reaction, 'emoticon', None)
        if e:
            out.append({'e': e, 'n': res.count, 'mine': res.chosen_order is not None})
    return out


def human_size(n):
    for u in ('Б', 'КБ', 'МБ', 'ГБ'):
        if n < 1024:
            return f'{n:.0f} {u}' if u == 'Б' else f'{n:.1f} {u}'
        n /= 1024
    return f'{n:.1f} ТБ'


names = {}          # sender id → display name (for replies / forwards)


async def name_of(peer_id):
    if peer_id in names:
        return names[peer_id]
    try:
        names[peer_id] = get_display_name(await tg.get_entity(peer_id))
    except Exception:
        names[peer_id] = ''
    return names[peer_id]


async def ser(m):
    kind, path, w, h, label = await media_of(m)
    d = {
        'id': m.id, 'out': bool(m.out), 'date': int(m.date.timestamp()),
        'text': m.message or '', 'kind': kind, 'media': path, 'w': w, 'h': h, 'label': label,
        'reactions': reactions_of(m), 'read': bool(m.out and m.id <= read_out_max),
        'edited': bool(m.edit_date) and not m.edit_hide, 'reply': None, 'fwd': '', 'file': '', 'dur': 0,
    }
    if m.file and kind in ('other', 'voice', 'video'):
        d['file'] = (m.file.name or '') + (' · ' + human_size(m.file.size) if m.file.size else '')
    if m.voice or m.video_note or m.video:
        d['dur'] = int(getattr(m.file, 'duration', 0) or 0)
    if m.fwd_from:
        f = m.fwd_from
        d['fwd'] = f.from_name or (await name_of(f.from_id) if f.from_id else 'скрытый пользователь')
    if m.reply_to and m.reply_to.reply_to_msg_id:
        rid = m.reply_to.reply_to_msg_id
        src = next((h for h in history if h['id'] == rid), None)
        if src is None:
            try:
                rm = await tg.get_messages(peer, ids=rid)
                if rm:
                    src = {'out': rm.out, 'text': rm.message or '', 'label': '📷 фото' if rm.photo else ('стикер' if rm.sticker else ('🎤 голосовое' if rm.voice else '📎 вложение' if rm.media else ''))}
            except Exception:
                src = None
        if src:
            d['reply'] = {'id': rid, 'who': 'Вы' if src['out'] else peer_info.get('name', ''),
                          'text': (src.get('text') or src.get('label') or '')[:120]}
    return d


def status_of(user):
    s = user.status
    if isinstance(s, types.UserStatusOnline):
        return True, 'в сети'
    if isinstance(s, types.UserStatusOffline):
        t = s.was_online.timestamp()
        mins = int((time.time() - t) // 60)
        if mins < 1:
            return False, 'был(а) только что'
        if mins < 60:
            return False, f'был(а) {mins} мин назад'
        lt = time.localtime(t)
        if time.time() - t < 86400:
            return False, time.strftime('был(а) в %H:%M', lt)
        return False, time.strftime('был(а) %d.%m в %H:%M', lt)
    if isinstance(s, types.UserStatusRecently):
        return False, 'был(а) недавно'
    return False, 'давно не заходил(а)'


async def refresh_peer():
    user = await tg.get_entity(peer)
    CACHE.mkdir(parents=True, exist_ok=True)
    av = CACHE / 'avatar.jpg'
    try:
        await tg.download_profile_photo(user, file=str(av), download_big=False)
    except Exception:
        pass
    online, text = status_of(user)
    peer_info.update(name=get_display_name(user), avatar=str(av) if av.exists() else '', status=text, online=online)
    await send_all({'t': 'peer', **peer_info})


# ------------------------------------------------------------------------------- websocket
async def handler(ws):
    path = ws.request.path if hasattr(ws, 'request') else ws.path
    got = path.split('token=', 1)[1].split('&')[0] if 'token=' in path else ''
    if not secrets.compare_digest(got, token()):
        await ws.close(code=4001, reason='bad token')
        return
    clients.add(ws)
    try:
        await ws.send(json.dumps({'t': 'state', **state}, ensure_ascii=False))
        if peer_info:
            await ws.send(json.dumps({'t': 'peer', **peer_info}, ensure_ascii=False))
        await ws.send(json.dumps({'t': 'history', 'msgs': history}, ensure_ascii=False))
        await ws.send(json.dumps({'t': 'unread', 'n': unread}))
        async for raw in ws:
            try:
                await command(json.loads(raw))
            except Exception as e:
                print('command error', repr(e), file=sys.stderr)
                await send_all({'t': 'toast', 'text': 'Ошибка: ' + str(e)[:120]})
    finally:
        clients.discard(ws)


last_typing = 0.0


recording = {'proc': None, 't0': 0.0, 'path': None}
sticker_docs = {}


async def progress(cur, total):
    await send_all({'t': 'progress', 'p': (cur / total) if total else 0})


async def open_external(path):
    await asyncio.create_subprocess_exec('xdg-open', str(path), stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)


async def wl(*args):
    p = await asyncio.create_subprocess_exec(WL_PASTE, *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    try:
        out, _ = await asyncio.wait_for(p.communicate(), 5)
    except asyncio.TimeoutError:
        p.kill()
        return b''
    return out if p.returncode == 0 else b''


async def paste():
    """Clipboard → files to attach: copied files (Dolphin…) or an image (screenshot…). [] = plain text."""
    if not os.path.exists(WL_PASTE):
        return []
    kinds = (await wl('--list-types')).decode(errors='ignore').split()
    if 'text/uri-list' in kinds:
        files = []
        for line in (await wl('--no-newline', '--type', 'text/uri-list')).decode(errors='ignore').splitlines():
            u = urlparse(line.strip())
            if u.scheme == 'file' and os.path.isfile(unquote(u.path)):
                files.append(unquote(u.path))
        if files:
            return files
    mime = next((m for m in IMAGE_TYPES if m in kinds), None)
    if not mime:
        return []
    data = await wl('--type', mime)
    if not data:
        return []
    d = cache_dir() / 'clip'
    d.mkdir(exist_ok=True)
    os.chmod(d, 0o700)
    for old in d.glob('clip-*'):                 # forget pastes nobody sent
        if time.time() - old.stat().st_mtime > 86400:
            old.unlink(missing_ok=True)
    ext = {'image/jpeg': '.jpg', 'image/webp': '.webp', 'image/gif': '.gif'}.get(mime, '.png')
    f = d / f'clip-{int(time.time() * 1000)}{ext}'
    if mime == 'image/bmp':                       # Telegram wants png/jpg; ask for png instead
        data, f = await wl('--type', 'image/png') or data, f.with_suffix('.png')
    f.write_bytes(data)
    os.chmod(f, 0o600)
    return [str(f)]


async def command(c):
    global unread, last_typing
    if c.get('t') == 'paste':
        await send_all({'t': 'clip', 'files': await paste()})
        return
    if state['state'] != 'ok':
        return
    t = c.get('t')
    reply = int(c['reply']) if c.get('reply') else None
    if t == 'send' and c.get('text', '').strip():
        m = await tg.send_message(peer, c['text'].strip()[:4096], reply_to=reply)
        await upsert(m, 'msg')
    elif t == 'send_file':
        path = Path(c['path'].replace('file://', ''))
        if not path.is_file():
            await send_all({'t': 'toast', 'text': 'Файл не найден'})
            return
        img = path.suffix.lower() in ('.jpg', '.jpeg', '.png', '.webp', '.heic')
        await send_all({'t': 'progress', 'p': 0})
        m = await tg.send_file(peer, str(path), caption=(c.get('caption') or '')[:1024], reply_to=reply,
                               force_document=not img and path.suffix.lower() not in ('.mp4', '.mov', '.webm', '.gif', '.mp3', '.ogg', '.m4a'),
                               progress_callback=progress)
        await send_all({'t': 'progress', 'p': -1})
        if path.parent == CACHE / 'clip':
            path.unlink(missing_ok=True)          # pasted screenshot: sent, no need to keep it
        await upsert(m, 'msg')
    elif t == 'edit' and c.get('text', '').strip():
        m = await tg.edit_message(peer, int(c['id']), c['text'].strip()[:4096])
        await upsert(m, 'edit')
    elif t == 'delete':
        await tg.delete_messages(peer, [int(c['id'])], revoke=True)
        history[:] = [h for h in history if h['id'] != int(c['id'])]
        await send_all({'t': 'del', 'ids': [int(c['id'])]})
    elif t == 'more':
        before = int(c.get('before') or 0)
        msgs = await tg.get_messages(peer, limit=30, offset_id=before)
        await send_all({'t': 'older', 'msgs': [await ser(m) for m in reversed(msgs)]})
    elif t == 'open':
        m = await tg.get_messages(peer, ids=int(c['id']))
        if not m or not m.media:
            return
        await send_all({'t': 'toast', 'text': 'Открываю…'})
        target = cache_dir() / 'full'
        target.mkdir(exist_ok=True)
        os.chmod(target, 0o700)
        f = await tg.download_media(m, file=str(target) + '/', progress_callback=progress)
        await send_all({'t': 'progress', 'p': -1})
        if f:
            os.chmod(f, 0o600)
            await open_external(f)
    elif t == 'voice':
        m = await tg.get_messages(peer, ids=int(c['id']))
        if m and (m.voice or m.audio):
            p = cache_dir() / f'a{m.id}.ogg'
            if not p.exists():
                await tg.download_media(m, file=str(p))
                os.chmod(p, 0o600)
            await send_all({'t': 'voice', 'id': m.id, 'path': str(p)})
    elif t == 'stickers':
        res = await tg(functions.messages.GetRecentStickersRequest(hash=0))
        items = []
        for doc in (getattr(res, 'stickers', None) or [])[:30]:
            sticker_docs[doc.id] = doc
            p = cache_dir() / f's{doc.id}.webp'
            if not p.exists():
                try:
                    if doc.mime_type == 'image/webp':
                        await tg.download_media(doc, file=str(p))
                    elif doc.thumbs:
                        await tg.download_media(doc, file=str(p), thumb=-1)
                except Exception:
                    continue
            if p.exists():
                items.append({'id': str(doc.id), 'path': str(p)})
        await send_all({'t': 'stickers', 'items': items})
    elif t == 'send_sticker':
        doc = sticker_docs.get(int(c['id']))
        if doc:
            m = await tg.send_file(peer, doc, reply_to=reply)
            await upsert(m, 'msg')
    elif t == 'rec_start' and recording['proc'] is None:
        p = cache_dir() / f'rec-{int(time.time())}.ogg'
        recording.update(path=p, t0=time.time(), proc=await asyncio.create_subprocess_exec(
            'ffmpeg', '-loglevel', 'error', '-y', '-f', 'pulse', '-i', 'default', '-ac', '1', '-ar', '48000',
            '-c:a', 'libopus', '-b:a', '32k', '-application', 'voip', str(p),
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL))
        asyncio.create_task(rec_ticker())
    elif t == 'rec_stop' and recording['proc'] is not None:
        proc, p, dur = recording['proc'], recording['path'], time.time() - recording['t0']
        recording.update(proc=None)
        try:
            proc.stdin.write(b'q')           # ffmpeg finishes the ogg cleanly on "q"
            await proc.stdin.drain()
        except Exception:
            proc.terminate()
        await proc.wait()
        await send_all({'t': 'recording', 'on': False, 'sec': 0})
        if c.get('send') and dur >= 0.7 and p.exists():
            os.chmod(p, 0o600)
            m = await tg.send_file(peer, str(p), voice_note=True, reply_to=reply,
                                   attributes=[types.DocumentAttributeAudio(duration=int(dur), voice=True)])
            await upsert(m, 'msg')
        p.unlink(missing_ok=True)
    elif t == 'react':
        m = await tg.get_messages(peer, ids=int(c['id']))
        if not m:
            return
        mine = [r['e'] for r in reactions_of(m) if r['mine']]
        rx = [] if c['e'] in mine else [types.ReactionEmoji(emoticon=c['e'])]
        await tg(functions.messages.SendReactionRequest(peer=peer, msg_id=m.id, reaction=rx))
        await upsert(await tg.get_messages(peer, ids=m.id), 'edit')
    elif t == 'read':
        if unread:
            await tg.send_read_acknowledge(peer)
            unread = 0
            await send_all({'t': 'unread', 'n': 0})
    elif t == 'typing' and time.time() - last_typing > 4:
        last_typing = time.time()
        await tg(functions.messages.SetTypingRequest(peer=peer, action=types.SendMessageTypingAction()))


async def rec_ticker():
    while recording['proc'] is not None:
        sec = int(time.time() - recording['t0'])
        await send_all({'t': 'recording', 'on': True, 'sec': sec})
        if sec >= 300:                         # 5 min safety limit
            await command({'t': 'rec_stop', 'send': True})
            break
        await asyncio.sleep(0.5)


async def upsert(m, kind):
    s = await ser(m)
    for i, old in enumerate(history):
        if old['id'] == s['id']:
            history[i] = s
            await send_all({'t': 'edit', 'm': s})
            return
    history.append(s)
    del history[:-KEEP]
    await send_all({'t': 'msg' if kind == 'msg' else 'edit', 'm': s})


# ------------------------------------------------------------------------------- telegram
async def telegram():
    global tg, peer, read_out_max, unread, history
    while True:
        if not CFG.exists():
            await set_state('no_config', 'Запусти tg-login, чтобы подключить Telegram')
            await asyncio.sleep(10)
            continue
        cfg = json.loads(CFG.read_text())
        private(CFG)
        if not cfg.get('peer'):
            await set_state('need_login', 'Запусти midnight-pulse-tg-login')
            await asyncio.sleep(10)
            continue
        DATA.mkdir(parents=True, exist_ok=True)
        os.chmod(DATA, 0o700)
        tg = TelegramClient(str(DATA / 'widget'), int(cfg['api_id']), cfg['api_hash'],
                            device_model='Midnight Pulse widget', system_version='KDE Plasma', app_version='1.0')
        try:
            await tg.connect()
            if not await tg.is_user_authorized():
                await set_state('need_login', 'Нужен вход: запусти tg-login')
                await tg.disconnect()
                await asyncio.sleep(30)
                continue
            for f in DATA.glob('*.session*'):
                os.chmod(f, 0o600)
            peer = await tg.get_input_entity(int(cfg['peer']))
            dlg = (await tg(functions.messages.GetPeerDialogsRequest(peers=[peer]))).dialogs[0]
            read_out_max, unread = dlg.read_outbox_max_id, dlg.unread_count
            await refresh_peer()
            msgs = await tg.get_messages(peer, limit=KEEP)
            history = [await ser(m) for m in reversed(msgs)]
            await set_state('ok')
            await send_all({'t': 'history', 'msgs': history})
            await send_all({'t': 'unread', 'n': unread})

            pid = (await tg.get_entity(peer)).id

            @tg.on(events.NewMessage(chats=[pid]))
            async def on_new(e):
                global unread
                await upsert(e.message, 'msg')
                if not e.message.out:
                    unread += 1
                    await send_all({'t': 'unread', 'n': unread})

            @tg.on(events.MessageEdited(chats=[pid]))
            async def on_edit(e):
                await upsert(e.message, 'edit')

            @tg.on(events.MessageDeleted())
            async def on_del(e):
                ids = [i for i in e.deleted_ids if any(h['id'] == i for h in history)]
                if ids:
                    history[:] = [h for h in history if h['id'] not in ids]
                    await send_all({'t': 'del', 'ids': ids})

            @tg.on(events.MessageRead(chats=[pid], inbox=False))
            async def on_read(e):
                global read_out_max
                read_out_max = max(read_out_max, e.max_id)
                for h in history:
                    if h['out']:
                        h['read'] = h['id'] <= read_out_max
                await send_all({'t': 'read', 'max': read_out_max})

            @tg.on(events.MessageRead(chats=[pid], inbox=True))
            async def on_read_here(e):          # read on the phone → clear our badge
                global unread
                unread = 0
                await send_all({'t': 'unread', 'n': 0})

            @tg.on(events.UserUpdate(chats=[pid]))
            async def on_user(e):
                if e.typing:
                    await send_all({'t': 'typing'})
                if e.status is not None:
                    await refresh_peer()

            @tg.on(events.Raw(types.UpdateMessageReactions))
            async def on_reactions(u):
                if getattr(u.peer, 'user_id', None) == pid:
                    m = await tg.get_messages(peer, ids=u.msg_id)
                    if m:
                        await upsert(m, 'edit')

            async def status_tick():          # keeps "был(а) N мин назад" fresh
                while tg.is_connected():
                    await asyncio.sleep(60)
                    await refresh_peer()
            asyncio.create_task(status_tick())
            await tg.run_until_disconnected()
        except Exception as e:
            print('telegram error', repr(e), file=sys.stderr)
            await set_state('error', str(e)[:200])
        finally:
            try:
                await tg.disconnect()
            except Exception:
                pass
        await asyncio.sleep(10)


async def main():
    token()
    async with websockets.serve(handler, '127.0.0.1', PORT, max_size=2 ** 20):
        await telegram()


if __name__ == '__main__':
    asyncio.run(main())
