import axios from "axios";

export const getYamarecoData = async (req, res) => {
  const { name } = req.query;
  const yamarecoApiKey = process.env.YAMARECO_API_KEY;

  try {
    const url = `https://api.yamareco.com/v1/mountain?name=${encodeURIComponent(name)}&key=${yamarecoApiKey}`;
    const response = await axios.get(url);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
