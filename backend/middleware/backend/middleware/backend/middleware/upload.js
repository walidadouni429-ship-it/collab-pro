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
