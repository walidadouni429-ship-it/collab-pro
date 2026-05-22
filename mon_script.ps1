
foreach ($f in $folders) {
    New-Item -ItemType Directory -Force -Path $f | Out-Null
}
Write-Host "✅ Dossiers créés" -ForegroundColor Green

# ================================================================
# FICHIER : backend/package.json
# ================================================================
Write-Host "📝 Création des fichiers..." -ForegroundColor Yellow

@'
{
  "name": "collab-pro",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "node server.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "jsonwebtoken": "^9.0.2",
    "multer": "^1.4.5-lts.1",
    "passport": "^0.7.0",
    "passport-github2": "^0.1.12",
    "passport-google-oauth20": "^2.0.0",
    "sharp": "^0.33.0",
    "socket.io": "^4.7.2",
    "sqlite3": "^5.1.6",
    "uuid": "^9.0.1"
  }
}
'@ | Set-Content -Path "backend\package.json" -Encoding UTF8

# ================================================================
# FICHIER : backend/.env
# ================================================================
@'
PORT=3000
JWT_SECRET=mon_secret_jwt_a_changer_2024
SESSION_SECRET=mon_secret_session_2024
APP_URL=http://localhost:3000
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_CALLBACK_URL=http://localhost:3000/api/auth/google/callback
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
GITHUB_CALLBACK_URL=http://localhost:3000/api/auth/github/callback
'@ | Set-Content -Path "backend\.env" -Encoding UTF8

# ================================================================
# FICHIER : backend/database.js
# ================================================================
@'
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, '../database/collab.db');
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) console.error('Database error:', err);
    else console.log('Connected to SQLite');
});

db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password TEXT,
        avatar TEXT,
        avatar_url TEXT,
        avatar_file TEXT,
        provider TEXT DEFAULT 'local',
        provider_id TEXT,
        language TEXT DEFAULT 'fr',
        role TEXT DEFAULT 'user',
        status TEXT DEFAULT 'offline',
        last_seen DATETIME,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS teams (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        owner_id INTEGER,
        invite_code TEXT UNIQUE,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS team_members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER,
        user_id INTEGER,
        role TEXT DEFAULT 'member',
        joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(team_id, user_id)
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER,
        name TEXT NOT NULL,
        description TEXT,
        status TEXT DEFAULT 'active',
        priority TEXT DEFAULT 'medium',
        start_date DATE,
        end_date DATE,
        budget REAL,
        created_by INTEGER,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER,
        name TEXT NOT NULL,
        description TEXT,
        status TEXT DEFAULT 'todo',
        priority TEXT DEFAULT 'medium',
        assignee_id INTEGER,
        due_date DATE,
        created_by INTEGER,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER,
        user_id INTEGER,
        content TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER,
        project_id INTEGER,
        user_id INTEGER,
        filename TEXT NOT NULL,
        original_name TEXT NOT NULL,
        mime_type TEXT,
        size INTEGER,
        path TEXT NOT NULL,
        thumbnail TEXT,
        uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);

    db.run(`CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        type TEXT,
        title TEXT,
        message TEXT,
        link TEXT,
        is_read BOOLEAN DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);

    console.log('All tables created');
});

module.exports = db;
'@ | Set-Content -Path "backend\database.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/middleware/auth.js
# ================================================================
@'
const jwt = require('jsonwebtoken');
require('dotenv').config();

const SECRET = process.env.JWT_SECRET || 'fallback_secret';

function authenticateToken(req, res, next) {
    const token = req.headers['authorization']?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'No token' });
    
    jwt.verify(token, SECRET, (err, user) => {
        if (err) return res.status(403).json({ error: 'Invalid token' });
        req.user = user;
        next();
    });
}

module.exports = { authenticateToken, SECRET };
'@ | Set-Content -Path "backend\middleware\auth.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/middleware/upload.js
# ================================================================
@'
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');

['uploads/avatars', 'uploads/tasks'].forEach(dir => {
    const fullPath = path.join(__dirname, '../../', dir);
    if (!fs.existsSync(fullPath)) fs.mkdirSync(fullPath, { recursive: true });
});

const taskStorage = multer.diskStorage({
    destination: (req, file, cb) => cb(null, path.join(__dirname, '../../uploads/tasks')),
    filename: (req, file, cb) => cb(null, Date.now() + '-' + uuidv4() + path.extname(file.originalname))
});

const avatarStorage = multer.diskStorage({
    destination: (req, file, cb) => cb(null, path.join(__dirname, '../../uploads/avatars')),
    filename: (req, file, cb) => cb(null, 'avatar-' + req.user.id + '-' + Date.now() + path.extname(file.originalname))
});

const fileFilter = (req, file, cb) => cb(null, true);
const avatarFilter = (req, file, cb) => {
    cb(null, ['image/jpeg', 'image/png', 'image/gif', 'image/webp'].includes(file.mimetype));
};

module.exports = {
    uploadTaskFiles: multer({ storage: taskStorage, fileFilter, limits: { fileSize: 50 * 1024 * 1024 } }),
    uploadAvatar: multer({ storage: avatarStorage, fileFilter: avatarFilter, limits: { fileSize: 5 * 1024 * 1024 } })
};
'@ | Set-Content -Path "backend\middleware\upload.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/config/oauth.js
# ================================================================
@'
const passport = require('passport');
const GoogleStrategy = require('passport-google-oauth20').Strategy;
const GitHubStrategy = require('passport-github2').Strategy;
const db = require('../database');
require('dotenv').config();

passport.serializeUser((user, done) => done(null, user.id));
passport.deserializeUser((id, done) => {
    db.get('SELECT * FROM users WHERE id = ?', [id], (err, user) => done(err, user));
});

function handleOAuthUser(profile, provider, done) {
    const email = profile.emails?.[0]?.value || profile.username + '@' + provider + '.local';
    const username = profile.displayName || profile.username;
    const avatarUrl = profile.photos?.[0]?.value;
    const providerId = profile.id;
    
    db.get('SELECT * FROM users WHERE email = ? OR (provider = ? AND provider_id = ?)',
        [email, provider, providerId], (err, user) => {
        if (err) return done(err);
        if (user) {
            db.run('UPDATE users SET avatar_url = ?, status = ?, provider = ?, provider_id = ? WHERE id = ?',
                [avatarUrl, 'online', provider, providerId, user.id]);
            return done(null, user);
        }
        const initials = username.substring(0, 2).toUpperCase();
        db.run('INSERT INTO users (username, email, avatar, avatar_url, provider, provider_id, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [username, email, initials, avatarUrl, provider, providerId, 'online'],
        function(err) {
            if (err) return done(err);
            db.get('SELECT * FROM users WHERE id = ?', [this.lastID], (err, newUser) => done(null, newUser));
        });
    });
}

if (process.env.GOOGLE_CLIENT_ID) {
    passport.use(new GoogleStrategy({
        clientID: process.env.GOOGLE_CLIENT_ID,
        clientSecret: process.env.GOOGLE_CLIENT_SECRET,
        callbackURL: process.env.GOOGLE_CALLBACK_URL
    }, (at, rt, profile, done) => handleOAuthUser(profile, 'google', done)));
}

if (process.env.GITHUB_CLIENT_ID) {
    passport.use(new GitHubStrategy({
        clientID: process.env.GITHUB_CLIENT_ID,
        clientSecret: process.env.GITHUB_CLIENT_SECRET,
        callbackURL: process.env.GITHUB_CALLBACK_URL,
        scope: ['user:email']
    }, (at, rt, profile, done) => handleOAuthUser(profile, 'github', done)));
}

module.exports = passport;
'@ | Set-Content -Path "backend\config\oauth.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/routes/auth.js
# ================================================================
@'
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const passport = require('passport');
const db = require('../database');
const { SECRET, authenticateToken } = require('../middleware/auth');

const router = express.Router();
const APP_URL = process.env.APP_URL || 'http://localhost:3000';

router.post('/register', async (req, res) => {
    const { username, email, password } = req.body;
    if (!username || !email || !password) return res.status(400).json({ error: 'All fields required' });
    try {
        const hash = await bcrypt.hash(password, 10);
        const avatar = username.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
        db.run('INSERT INTO users (username, email, password, avatar) VALUES (?, ?, ?, ?)',
            [username, email, hash, avatar],
        function(err) {
            if (err) return res.status(400).json({ error: 'Email already exists' });
            res.json({ message: 'Account created', userId: this.lastID });
        });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

router.post('/login', (req, res) => {
    const { email, password } = req.body;
    db.get('SELECT * FROM users WHERE email = ?', [email], async (err, user) => {
        if (err || !user) return res.status(400).json({ error: 'Invalid credentials' });
        if (!user.password) return res.status(400).json({ error: 'Use OAuth' });
        const valid = await bcrypt.compare(password, user.password);
        if (!valid) return res.status(400).json({ error: 'Wrong password' });
        const token = jwt.sign({ id: user.id, username: user.username, email: user.email }, SECRET, { expiresIn: '7d' });
        db.run('UPDATE users SET status = ?, last_seen = ? WHERE id = ?', ['online', new Date().toISOString(), user.id]);
        res.json({
            token,
            user: { id: user.id, username: user.username, email: user.email, avatar: user.avatar, avatar_url: user.avatar_url, provider: user.provider }
        });
    });
});

router.get('/me', authenticateToken, (req, res) => {
    db.get('SELECT id, username, email, avatar, avatar_url, role, provider FROM users WHERE id = ?',
        [req.user.id], (err, user) => res.json(user));
});

router.get('/providers', (req, res) => {
    res.json({
        google: !!process.env.GOOGLE_CLIENT_ID,
        github: !!process.env.GITHUB_CLIENT_ID
    });
});

router.get('/google', passport.authenticate('google', { scope: ['profile', 'email'] }));
router.get('/google/callback',
    passport.authenticate('google', { failureRedirect: '/?error=google', session: false }),
    (req, res) => {
        const token = jwt.sign({ id: req.user.id, username: req.user.username, email: req.user.email }, SECRET, { expiresIn: '7d' });
        res.redirect(APP_URL + '/?token=' + token + '&user=' + encodeURIComponent(JSON.stringify({
            id: req.user.id, username: req.user.username, email: req.user.email,
            avatar: req.user.avatar, avatar_url: req.user.avatar_url, provider: 'google'
        })));
    }
);

router.get('/github', passport.authenticate('github', { scope: ['user:email'] }));
router.get('/github/callback',
    passport.authenticate('github', { failureRedirect: '/?error=github', session: false }),
    (req, res) => {
        const token = jwt.sign({ id: req.user.id, username: req.user.username, email: req.user.email }, SECRET, { expiresIn: '7d' });
        res.redirect(APP_URL + '/?token=' + token + '&user=' + encodeURIComponent(JSON.stringify({
            id: req.user.id, username: req.user.username, email: req.user.email,
            avatar: req.user.avatar, avatar_url: req.user.avatar_url, provider: 'github'
        })));
    }
);

module.exports = router;
'@ | Set-Content -Path "backend\routes\auth.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/routes/teams.js
# ================================================================
@'
const express = require('express');
const db = require('../database');
const { authenticateToken } = require('../middleware/auth');
const router = express.Router();

router.get('/', authenticateToken, (req, res) => {
    db.all(`SELECT t.*, tm.role as my_role,
        (SELECT COUNT(*) FROM team_members WHERE team_id = t.id) as member_count,
        (SELECT COUNT(*) FROM projects WHERE team_id = t.id) as project_count
        FROM teams t JOIN team_members tm ON t.id = tm.team_id
        WHERE tm.user_id = ? ORDER BY t.created_at DESC`,
        [req.user.id], (err, teams) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(teams);
    });
});

router.post('/', authenticateToken, (req, res) => {
    const { name, description } = req.body;
    const inviteCode = Math.random().toString(36).substring(2, 10).toUpperCase();
    db.run('INSERT INTO teams (name, description, owner_id, invite_code) VALUES (?, ?, ?, ?)',
        [name, description, req.user.id, inviteCode],
    function(err) {
        if (err) return res.status(500).json({ error: err.message });
        const teamId = this.lastID;
        db.run('INSERT INTO team_members (team_id, user_id, role) VALUES (?, ?, ?)',
            [teamId, req.user.id, 'owner']);
        res.json({ id: teamId, invite_code: inviteCode });
    });
});

router.get('/:id/members', authenticateToken, (req, res) => {
    db.all(`SELECT u.id, u.username, u.email, u.avatar, u.avatar_url, u.status, tm.role
        FROM team_members tm JOIN users u ON tm.user_id = u.id WHERE tm.team_id = ?`,
        [req.params.id], (err, members) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(members);
    });
});

router.post('/join', authenticateToken, (req, res) => {
    db.get('SELECT * FROM teams WHERE invite_code = ?', [req.body.invite_code], (err, team) => {
        if (err || !team) return res.status(404).json({ error: 'Invalid code' });
        db.run('INSERT INTO team_members (team_id, user_id) VALUES (?, ?)',
            [team.id, req.user.id], function(err) {
            if (err) return res.status(400).json({ error: 'Already member' });
            res.json({ message: 'Joined', team_id: team.id });
        });
    });
});

router.delete('/:id', authenticateToken, (req, res) => {
    db.get('SELECT owner_id FROM teams WHERE id = ?', [req.params.id], (err, team) => {
        if (!team || team.owner_id !== req.user.id) return res.status(403).json({ error: 'Not owner' });
        db.run('DELETE FROM teams WHERE id = ?', [req.params.id]);
        db.run('DELETE FROM team_members WHERE team_id = ?', [req.params.id]);
        db.run('DELETE FROM projects WHERE team_id = ?', [req.params.id]);
        res.json({ message: 'Deleted' });
    });
});

module.exports = router;
'@ | Set-Content -Path "backend\routes\teams.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/routes/projects.js
# ================================================================
@'
const express = require('express');
const db = require('../database');
const { authenticateToken } = require('../middleware/auth');
const router = express.Router();

router.get('/team/:teamId', authenticateToken, (req, res) => {
    db.all(`SELECT p.*, u.username as creator_name,
        (SELECT COUNT(*) FROM tasks WHERE project_id = p.id) as task_count,
        (SELECT COUNT(*) FROM tasks WHERE project_id = p.id AND status = 'done') as done_count
        FROM projects p LEFT JOIN users u ON p.created_by = u.id
        WHERE p.team_id = ? ORDER BY p.created_at DESC`,
        [req.params.teamId], (err, projects) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(projects);
    });
});

router.post('/', authenticateToken, (req, res) => {
    const { team_id, name, description, status, priority, start_date, end_date, budget } = req.body;
    db.run(`INSERT INTO projects (team_id, name, description, status, priority, start_date, end_date, budget, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [team_id, name, description, status || 'active', priority || 'medium', start_date, end_date, budget, req.user.id],
    function(err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ id: this.lastID });
    });
});

router.put('/:id', authenticateToken, (req, res) => {
    const { name, description, status, priority, start_date, end_date, budget } = req.body;
    db.run(`UPDATE projects SET name=?, description=?, status=?, priority=?, start_date=?, end_date=?, budget=? WHERE id=?`,
        [name, description, status, priority, start_date, end_date, budget, req.params.id],
        (err) => res.json({ message: err ? 'Error' : 'Updated' }));
});

router.delete('/:id', authenticateToken, (req, res) => {
    db.run('DELETE FROM projects WHERE id = ?', [req.params.id]);
    db.run('DELETE FROM tasks WHERE project_id = ?', [req.params.id]);
    res.json({ message: 'Deleted' });
});

module.exports = router;
'@ | Set-Content -Path "backend\routes\projects.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/routes/tasks.js
# ================================================================
@'
const express = require('express');
const db = require('../database');
const { authenticateToken } = require('../middleware/auth');
const router = express.Router();

router.get('/project/:projectId', authenticateToken, (req, res) => {
    db.all(`SELECT t.*, u.username as assignee_name, u.avatar as assignee_avatar,
        (SELECT COUNT(*) FROM comments WHERE task_id = t.id) as comment_count,
        (SELECT COUNT(*) FROM files WHERE task_id = t.id) as file_count
        FROM tasks t LEFT JOIN users u ON t.assignee_id = u.id
        WHERE t.project_id = ? ORDER BY t.created_at DESC`,
        [req.params.projectId], (err, tasks) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(tasks);
    });
});

router.post('/', authenticateToken, (req, res) => {
    const { project_id, name, description, status, priority, assignee_id, due_date } = req.body;
    db.run(`INSERT INTO tasks (project_id, name, description, status, priority, assignee_id, due_date, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [project_id, name, description, status || 'todo', priority || 'medium', assignee_id || null, due_date, req.user.id],
    function(err) {
        if (err) return res.status(500).json({ error: err.message });
        if (assignee_id) {
            db.run('INSERT INTO notifications (user_id, type, title, message) VALUES (?, ?, ?, ?)',
                [assignee_id, 'task_assigned', 'Nouvelle tache', 'Assignee: ' + name]);
        }
        res.json({ id: this.lastID });
    });
});

router.put('/:id', authenticateToken, (req, res) => {
    const { name, description, status, priority, assignee_id, due_date } = req.body;
    db.run(`UPDATE tasks SET name=?, description=?, status=?, priority=?, assignee_id=?, due_date=?, updated_at=? WHERE id=?`,
        [name, description, status, priority, assignee_id, due_date, new Date().toISOString(), req.params.id],
        (err) => res.json({ message: err ? 'Error' : 'Updated' }));
});

router.delete('/:id', authenticateToken, (req, res) => {
    db.run('DELETE FROM tasks WHERE id = ?', [req.params.id]);
    db.run('DELETE FROM comments WHERE task_id = ?', [req.params.id]);
    db.run('DELETE FROM files WHERE task_id = ?', [req.params.id]);
    res.json({ message: 'Deleted' });
});

module.exports = router;
'@ | Set-Content -Path "backend\routes\tasks.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/routes/comments.js
# ================================================================
@'
const express = require('express');
const db = require('../database');
const { authenticateToken } = require('../middleware/auth');
const router = express.Router();

router.get('/task/:taskId', authenticateToken, (req, res) => {
    db.all(`SELECT c.*, u.username, u.avatar, u.avatar_url
        FROM comments c JOIN users u ON c.user_id = u.id
        WHERE c.task_id = ? ORDER BY c.created_at ASC`,
        [req.params.taskId], (err, comments) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(comments);
    });
});

router.post('/', authenticateToken, (req, res) => {
    db.run('INSERT INTO comments (task_id, user_id, content) VALUES (?, ?, ?)',
        [req.body.task_id, req.user.id, req.body.content],
    function(err) {
        if (err) return res.status(500).json({ error: err.message });
        db.get(`SELECT c.*, u.username, u.avatar, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.id = ?`,
            [this.lastID], (err, comment) => res.json(comment));
    });
});

router.delete('/:id', authenticateToken, (req, res) => {
    db.run('DELETE FROM comments WHERE id = ? AND user_id = ?',
        [req.params.id, req.user.id], (err) => res.json({ message: 'Deleted' }));
});

module.exports = router;
'@ | Set-Content -Path "backend\routes\comments.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/routes/files.js
# ================================================================
@'
const express = require('express');
const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const db = require('../database');
const { authenticateToken } = require('../middleware/auth');
const { uploadTaskFiles, uploadAvatar } = require('../middleware/upload');
const router = express.Router();

router.post('/upload/task/:taskId', authenticateToken, uploadTaskFiles.array('files', 10), async (req, res) => {
    if (!req.files || req.files.length === 0) return res.status(400).json({ error: 'No files' });
    const taskId = parseInt(req.params.taskId);
    db.get('SELECT project_id FROM tasks WHERE id = ?', [taskId], async (err, task) => {
        if (err || !task) {
            req.files.forEach(f => fs.unlinkSync(f.path));
            return res.status(404).json({ error: 'Task not found' });
        }
        const uploadedFiles = [];
        for (const file of req.files) {
            let thumbnail = null;
            if (file.mimetype.startsWith('image/') && file.mimetype !== 'image/svg+xml') {
                try {
                    const thumbName = 'thumb-' + file.filename;
                    await sharp(file.path).resize(200, 200, { fit: 'cover' })
                        .toFile(path.join(path.dirname(file.path), thumbName));
                    thumbnail = thumbName;
                } catch (e) {}
            }
            await new Promise((resolve) => {
                db.run(`INSERT INTO files (task_id, project_id, user_id, filename, original_name, mime_type, size, path, thumbnail)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [taskId, task.project_id, req.user.id, file.filename, file.originalname,
                     file.mimetype, file.size, file.path, thumbnail],
                function() {
                    uploadedFiles.push({ id: this.lastID, original_name: file.originalname });
                    resolve();
                });
            });
        }
        res.json({ message: 'Uploaded', files: uploadedFiles });
    });
});

router.get('/task/:taskId', authenticateToken, (req, res) => {
    db.all(`SELECT f.*, u.username as uploader_name FROM files f
        JOIN users u ON f.user_id = u.id WHERE f.task_id = ? ORDER BY f.uploaded_at DESC`,
        [req.params.taskId], (err, files) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(files.map(f => ({
            ...f,
            url: '/api/files/download/' + f.id,
            preview_url: f.thumbnail ? '/api/files/preview/' + f.id : null,
            view_url: '/api/files/view/' + f.id
        })));
    });
});

router.get('/download/:id', (req, res) => {
    db.get('SELECT * FROM files WHERE id = ?', [req.params.id], (err, file) => {
        if (err || !file || !fs.existsSync(file.path)) return res.status(404).send('Not found');
        res.download(file.path, file.original_name);
    });
});

router.get('/view/:id', (req, res) => {
    db.get('SELECT * FROM files WHERE id = ?', [req.params.id], (err, file) => {
        if (err || !file || !fs.existsSync(file.path)) return res.status(404).send('Not found');
        res.setHeader('Content-Type', file.mime_type);
        fs.createReadStream(file.path).pipe(res);
    });
});

router.get('/preview/:id', (req, res) => {
    db.get('SELECT * FROM files WHERE id = ?', [req.params.id], (err, file) => {
        if (err || !file || !file.thumbnail) return res.status(404).send('No preview');
        const thumbPath = path.join(path.dirname(file.path), file.thumbnail);
        if (!fs.existsSync(thumbPath)) return res.status(404).send('Not found');
        res.setHeader('Content-Type', 'image/jpeg');
        fs.createReadStream(thumbPath).pipe(res);
    });
});

router.delete('/:id', authenticateToken, (req, res) => {
    db.get('SELECT * FROM files WHERE id = ?', [req.params.id], (err, file) => {
        if (err || !file) return res.status(404).json({ error: 'Not found' });
        if (file.user_id !== req.user.id) return res.status(403).json({ error: 'Permission denied' });
        try {
            if (fs.existsSync(file.path)) fs.unlinkSync(file.path);
            if (file.thumbnail) {
                const tp = path.join(path.dirname(file.path), file.thumbnail);
                if (fs.existsSync(tp)) fs.unlinkSync(tp);
            }
        } catch (e) {}
        db.run('DELETE FROM files WHERE id = ?', [req.params.id]);
        res.json({ message: 'Deleted' });
    });
});

module.exports = router;
'@ | Set-Content -Path "backend\routes\files.js" -Encoding UTF8

# ================================================================
# FICHIER : backend/server.js
# ================================================================
@'
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const session = require('express-session');
const path = require('path');
require('dotenv').config();

const passport = require('./config/oauth');
const db = require('./database');

const authRoutes = require('./routes/auth');
const teamRoutes = require('./routes/teams');
const projectRoutes = require('./routes/projects');
const taskRoutes = require('./routes/tasks');
const commentRoutes = require('./routes/comments');
const fileRoutes = require('./routes/files');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });
const PORT = process.env.PORT || 3000;

app.use(cors({ origin: true, credentials: true }));
app.use(express.json());
app.use(session({ secret: process.env.SESSION_SECRET || 'fallback', resave: false, saveUninitialized: false }));
app.use(passport.initialize());
app.use(passport.session());
app.use(express.static(path.join(__dirname, '../frontend')));

app.use('/api/auth', authRoutes);
app.use('/api/teams', teamRoutes);
app.use('/api/projects', projectRoutes);
app.use('/api/tasks', taskRoutes);
app.use('/api/comments', commentRoutes);
app.use('/api/files', fileRoutes);

app.get('/api/notifications', require('./middleware/auth').authenticateToken, (req, res) => {
    db.all('SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 20',
        [req.user.id], (err, rows) => res.json(rows || []));
});

app.get('/', (req, res) => res.sendFile(path.join(__dirname, '../frontend/index.html')));

const connectedUsers = new Map();

io.on('connection', (socket) => {
    socket.on('authenticate', (userData) => {
        socket.userId = userData.id;
        socket.username = userData.username;
        connectedUsers.set(userData.id, socket.id);
        db.run('UPDATE users SET status = ? WHERE id = ?', ['online', userData.id]);
        io.emit('user_status_changed', { userId: userData.id, status: 'online' });
    });

    socket.on('join_team', (teamId) => socket.join('team_' + teamId));
    socket.on('join_project', (projectId) => socket.join('project_' + projectId));
    socket.on('leave_project', (projectId) => socket.leave('project_' + projectId));
    
    socket.on('project_created', (data) => io.to('team_' + data.team_id).emit('project_created', data));
    socket.on('task_created', (data) => {
        io.to('project_' + data.project_id).emit('task_created', data);
        if (data.assignee_id && connectedUsers.has(data.assignee_id)) {
            io.to(connectedUsers.get(data.assignee_id)).emit('notification', {
                title: 'Nouvelle tache', message: socket.username + ' a assigne: ' + data.name
            });
        }
    });
    socket.on('task_updated', (data) => io.to('project_' + data.project_id).emit('task_updated', data));
    socket.on('comment_added', (data) => io.to('project_' + data.project_id).emit('comment_added', data));
    socket.on('file_uploaded', (data) => io.to('project_' + data.project_id).emit('file_uploaded', data));

    socket.on('disconnect', () => {
        if (socket.userId) {
            connectedUsers.delete(socket.userId);
            db.run('UPDATE users SET status = ?, last_seen = ? WHERE id = ?',
                ['offline', new Date().toISOString(), socket.userId]);
            io.emit('user_status_changed', { userId: socket.userId, status: 'offline' });
        }
    });
});

server.listen(PORT, () => {
    console.log('');
    console.log('========================================');
    console.log('  COLLAB PRO - SERVER RUNNING');
    console.log('  URL: http://localhost:' + PORT);
    console.log('  Database: SQLite');
    console.log('  Socket.IO: Ready');
    console.log('========================================');
    console.log('');
});
'@ | Set-Content -Path "backend\server.js" -Encoding UTF8

# ================================================================
# FICHIER : frontend/locales/fr.json
# ================================================================
@'
{
  "appName": "Collab Pro",
  "tagline": "Collaboration professionnelle",
  "login": "Connexion",
  "register": "Inscription",
  "logout": "Deconnexion",
  "email": "Email",
  "password": "Mot de passe",
  "fullName": "Nom complet",
  "loginButton": "Se connecter",
  "registerButton": "Creer le compte",
  "noAccount": "Pas de compte ?",
  "haveAccount": "Deja inscrit ?",
  "createAccount": "S'inscrire",
  "or": "OU",
  "continueWithGoogle": "Continuer avec Google",
  "continueWithGitHub": "Continuer avec GitHub",
  "myTeams": "Mes Equipes",
  "createTeam": "Creer equipe",
  "joinTeam": "Rejoindre",
  "newProject": "Nouveau projet",
  "newTask": "Nouvelle tache"
}
'@ | Set-Content -Path "frontend\locales\fr.json" -Encoding UTF8

# ================================================================
# FICHIER : frontend/locales/en.json
