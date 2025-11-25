require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const https = require('https');

const app = express();
app.use(cors());
app.use(express.json());

// Agent HTTPS que ignora certificado (para testes locais)
const insecureAgent = new https.Agent({
  rejectUnauthorized: false,
});

// Rota de teste interno
app.get('/ping', (req, res) => {
  res.json({
    ok: true,
    message: 'Backend NFC-e rodando com sucesso!',
  });
});

// Rota para testar status da SEFAZ via Webmania
app.get('/status', async (req, res) => {
  try {
    const response = await axios({
      method: 'GET',
      url: 'https://webmania.com.br/api/1/nfe/sefaz/',
      httpsAgent: insecureAgent,
      headers: {
        'Content-Type': 'application/json',
        'X-Consumer-Key': process.env.WM_API_KEY,
        'X-Consumer-Secret': process.env.WM_API_SECRET,
        'X-Access-Token': process.env.WM_ACCESS_TOKEN,
        'X-Access-Token-Secret': process.env.WM_ACCESS_TOKEN_SECRET,
      },
    });

    return res.json({
      ok: true,
      resultado: response.data,
    });
  } catch (error) {
    console.log('Erro Webmania (status):', error.response?.data || error);

    return res.status(500).json({
      ok: false,
      erro: error.response?.data || error.message,
    });
  }
});

// Rota para emitir NFC-e
app.post('/emitir-nfce', async (req, res) => {
  try {
    const dados = req.body; // JSON vindo do Postman/Flutter

    const response = await axios({
      method: 'POST',
            url: 'https://webmania.com.br/api/1/nfe/emissao/',

      httpsAgent: insecureAgent,
      headers: {
        'Content-Type': 'application/json',
        'X-Consumer-Key': process.env.WM_API_KEY,
        'X-Consumer-Secret': process.env.WM_API_SECRET,
        'X-Access-Token': process.env.WM_ACCESS_TOKEN,
        'X-Access-Token-Secret': process.env.WM_ACCESS_TOKEN_SECRET,
      },
      data: dados,
    });

    return res.json({
      ok: true,
      retorno: response.data,
    });
  } catch (error) {
    console.log('Erro emissão NFC-e:', error.response?.data || error);

    return res.status(500).json({
      ok: false,
      erro: error.response?.data || error.message,
    });
  }
});

const PORT = 3333;
app.listen(PORT, () => {
  console.log(`Servidor rodando na porta ${PORT}`);
});
