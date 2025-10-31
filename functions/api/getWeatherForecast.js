import axios from "axios";

export const getWeatherForecast = async (req, res) => {
  const { lat, lon } = req.query;
  const apiKey = process.env.OPENWEATHER_API_KEY;

  try {
    const url = `https://api.openweathermap.org/data/3.0/onecall?lat=${lat}&lon=${lon}&exclude=minutely,hourly,alerts&units=metric&lang=ja&appid=${apiKey}`;
    const response = await axios.get(url);

    const dailyForecast = response.data.daily.slice(0, 7).map((day) => ({
      date: new Date(day.dt * 1000).toLocaleDateString("ja-JP", {
        month: "numeric",
        day: "numeric",
        weekday: "short",
      }),
      weather: day.weather[0].description,
      tempMin: day.temp.min,
      tempMax: day.temp.max,
      wind: day.wind_speed,
      rainProb: Math.round(day.pop * 100),
      icon: `https://openweathermap.org/img/wn/${day.weather[0].icon}@2x.png`,
    }));

    res.json({ forecast: dailyForecast });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
