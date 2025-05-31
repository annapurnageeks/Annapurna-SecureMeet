const express = require('express');
const mongoose = require('mongoose');
const http = require('http');
const socketIo = require('socket.io');
const multer = require('multer');
const cors = require('cors');
const path = require('path');
const dotenv = require('dotenv');

dotenv.config();

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: '*', // Allow all origins for testing (restrict in production)
    methods: ['GET', 'POST'],
  },
});

app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, 'uploads/');
  },
  filename: (req, file, cb) => {
    cb(null, `${Date.now()}-${file.originalname}`);
  },
});
const upload = multer({ storage });

mongoose.connect(process.env.MONGO_URI, { useNewUrlParser: true, useUnifiedTopology: true })
  .then(() => console.log('Connected to MongoDB'))
  .catch((err) => console.error('MongoDB connection error:', err));

const Message = require('./models/Message');
const File = require('./models/File');
const Meeting = require('./models/Meeting');
const Note = require('./models/Note');

// Seed "Constant Meeting" if it doesn't exist
(async () => {
  const existingMeeting = await Meeting.findOne({ code: 'CONSTANT' });
  if (!existingMeeting) {
    const meeting = new Meeting({
      code: 'CONSTANT',
      title: 'Constant Meeting',
      createdBy: 'admin',
    });
    await meeting.save();
    console.log('Seeded Constant Meeting');
  }
})();

const peers = new Map(); // Store peer connections

io.on('connection', (socket) => {
  console.log('New client connected', socket.id);

  socket.on('message', async (msg) => {
    try {
      const message = new Message({
        userId: msg.userId,
        text: msg.text,
      });
      await message.save();
      io.emit('message', message);
    } catch (err) {
      console.error('Error saving message:', err);
    }
  });

  socket.on('note', async (note) => {
    try {
      const newNote = new Note({
        userId: note.userId,
        meetingCode: note.meetingCode,
        content: note.content,
      });
      await newNote.save();
      io.to(note.meetingCode).emit('note', newNote); // Emit to room only
    } catch (err) {
      console.error('Error saving note:', err);
    }
  });

  socket.on('join-meeting', (data) => {
    const { userId, meetingCode } = data;
    socket.join(meetingCode);
    peers.set(socket.id, { userId, meetingCode });
    // Broadcast to all in the room except the joining user
    socket.to(meetingCode).emit('user-joined', { userId, socketId: socket.id });
    // Send existing users to the new user
    const existingUsers = Array.from(peers.entries())
      .filter(([_, peer]) => peer.meetingCode === meetingCode && peer.userId !== userId)
      .map(([socketId, peer]) => ({ userId: peer.userId, socketId }));
    socket.emit('existing-users', existingUsers);
  });

  socket.on('offer', (data) => {
    const { sdp, toSocketId } = data;
    io.to(toSocketId).emit('offer', { sdp, fromSocketId: socket.id });
  });

  socket.on('answer', (data) => {
    const { sdp, toSocketId } = data;
    io.to(toSocketId).emit('answer', { sdp, fromSocketId: socket.id });
  });

  socket.on('ice-candidate', (data) => {
    const { candidate, toSocketId } = data;
    io.to(toSocketId).emit('ice-candidate', { candidate, fromSocketId: socket.id });
  });

  socket.on('disconnect', () => {
    const peer = peers.get(socket.id);
    if (peer) {
      io.to(peer.meetingCode).emit('user-left', { userId: peer.userId, socketId: socket.id });
      peers.delete(socket.id);
    }
    console.log('Client disconnected', socket.id);
  });
});

app.get('/messages', async (req, res) => {
  try {
    const messages = await Message.find().sort({ timestamp: 1 });
    res.json(messages);
  } catch (err) {
    res.status(500).send('Error fetching messages');
  }
});

app.post('/upload', upload.single('file'), async (req, res) => {
  try {
    const file = new File({
      userId: req.body.userId,
      fileName: req.file.filename,
      filePath: `/uploads/${req.file.filename}`,
    });
    await file.save();
    io.emit('file', file);
    res.json(file);
  } catch (err) {
    res.status(500).send('Error uploading file');
  }
});

app.get('/files', async (req, res) => {
  try {
    const files = await File.find().sort({ timestamp: 1 });
    res.json(files);
  } catch (err) {
    res.status(500).send('Error fetching files');
  }
});

app.get('/download/:fileName', (req, res) => {
  const fileName = req.params.fileName;
  const filePath = path.join(__dirname, 'uploads', fileName);
  res.download(filePath, fileName, (err) => {
    if (err) {
      res.status(404).send('File not found');
    }
  });
});

app.post('/meetings', async (req, res) => {
  try {
    const { code, title, createdBy } = req.body;
    const meeting = new Meeting({
      code,
      title,
      createdBy,
    });
    await meeting.save();
    res.status(201).json(meeting);
  } catch (err) {
    res.status(500).send('Error creating meeting');
  }
});

app.get('/meetings', async (req, res) => {
  try {
    const meetings = await Meeting.find();
    res.json(meetings);
  } catch (err) {
    res.status(500).send('Error fetching meetings');
  }
});

app.post('/notes', async (req, res) => {
  try {
    const note = new Note({
      userId: req.body.userId,
      meetingCode: req.body.meetingCode,
      content: req.body.content,
    });
    await note.save();
    io.to(req.body.meetingCode).emit('note', note); // Emit to room only
    res.status(201).json(note);
  } catch (err) {
    res.status(500).send('Error saving note');
  }
});

app.get('/notes/:meetingCode', async (req, res) => {
  try {
    const notes = await Note.find({ meetingCode: req.params.meetingCode }).sort({ timestamp: 1 });
    res.json(notes);
  } catch (err) {
    res.status(500).send('Error fetching notes');
  }
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});