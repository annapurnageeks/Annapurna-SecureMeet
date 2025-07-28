const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*' },
});

const rooms = {};

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  socket.on('join', ({ room, name }) => {
    socket.join(room);
    if (!rooms[room]) rooms[room] = [];
    rooms[room].push({ id: socket.id, name });
    console.log(`${name} joined room ${room}`);

    // Notify others in room that new user joined
    socket.to(room).emit('ready');
  });

  socket.on('offer', (data) => {
    socket.to(data.room).emit('offer', data);
  });

  socket.on('answer', (data) => {
    socket.to(data.room).emit('answer', data);
  });

  socket.on('candidate', (data) => {
    socket.to(data.room).emit('candidate', data.candidate);
  });

  // Chat message
  socket.on('chat-message', (data) => {
    io.to(data.room).emit('chat-message', data);
  });

  // File chunk
  socket.on('file-chunk', (data) => {
    io.to(data.room).emit('file-chunk', data);
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
    // Optional: remove user from rooms
  });
});

const PORT = 5000;
server.listen(PORT, () => console.log(`Signaling server running on port ${PORT}`));
