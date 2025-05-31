const mongoose = require('mongoose');

const noteSchema = new mongoose.Schema({
  userId: { type: String, required: true },
  meetingCode: { type: String, required: true },
  content: { type: String, required: true },
  timestamp: { type: Date, default: Date.now },
});

module.exports = mongoose.model('Note', noteSchema);