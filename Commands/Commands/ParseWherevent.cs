using System;
using System.Management.Automation;
using System.Net;
using System.Text;
using AngleSharp.Extensions;
using AngleSharp.Parser.Html;

namespace Commands
{
	[Cmdlet("Parse", "Wherevent")]
	public class ParseWherevent : Cmdlet
	{
		[Parameter(Mandatory = true, Position = 0)]
		public string Url { get; set; }

		[Parameter(Mandatory = true)]
		public string Proxy { get; set; }

		protected override void ProcessRecord()
		{
			var client = new WebClient
			{
				Encoding = Encoding.UTF8,
				Proxy = new WebProxy { Address = new Uri(Proxy), UseDefaultCredentials = true }
			};
			var response = client.DownloadString(Url);
			var parser = new HtmlParser();
			var document = parser.Parse(response);
			var events = document.QuerySelectorAll(".event");
			foreach (var @event in events)
			{
				WriteObject(new
				{
					Url = Url,
					Thumb = @event.QuerySelector("img").GetAttribute("src"),
					Title = @event.QuerySelector(".event_title").Text(),
					DateTime = @event.QuerySelector("time").GetAttribute("datetime"),
					Location = @event.QuerySelector(".event_location").Text().Trim(),
					FemaleCount = @event.QuerySelector(".event_femalecount").Text(),
					MaleCount = @event.QuerySelector(".event_malecount").Text()
				});
			}
		}
	}
}
