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
